# frozen_string_literal: true

# End-to-end test of the spice duplex protocol, with a fake heighliner instead
# of docker. Starts its own server, so:
#
#   ruby spice/test/protocol_test.rb
#
# The interesting cases are the ones a single HTTP request could not do: stdin,
# window size, resize mid-run, and ^C reaching the remote process group.

require 'pty'
require 'json'
require 'socket'
require 'io/console'
require 'timeout'
require 'tmpdir'
require 'English'

SPICE = File.expand_path('..', __dir__)
CLIENT = "#{SPICE}/client/heighliner"
SERVER = "#{SPICE}/server.rb"
FAKE_DIR = "#{SPICE}/test"

HEALTH_PORT = ENV.fetch('TEST_HEALTH_PORT', '7599')
STREAM_PORT = ENV.fetch('TEST_STREAM_PORT', '7600')
TOKEN = 'test-token'

CLIENT_ENV = {
  'SPICE_URL' => "http://127.0.0.1:#{HEALTH_PORT}",
  'SPICE_STREAM_PORT' => STREAM_PORT,
  'SPICE_TOKEN' => TOKEN
}.freeze

$failures = 0
$project = nil

def check(name, got, want)
  ok = want.is_a?(Regexp) ? want.match?(got.to_s) : got == want
  if ok
    puts "  ok   #{name}"
  else
    puts "  FAIL #{name}\n       want #{want.inspect}\n       got  #{got.inspect}"
    $failures += 1
  end
end

# Runs the client with no controlling terminal: how a pi agent invokes it.
def plain(*argv, input: nil, env: {}, chdir: $project)
  out = IO.popen(CLIENT_ENV.merge(env), ['ruby', CLIENT, *argv],
                 'r+', chdir: chdir, err: [:child, :out]) do |io|
    io.write(input) if input
    io.close_write
    io.read
  end
  [out, $CHILD_STATUS.exitstatus]
end

# Runs the client on a real pty: how a human in a terminal invokes it.
def interactive(*argv, rows: 24, cols: 80)
  reader, writer, pid = PTY.spawn(CLIENT_ENV, 'ruby', CLIENT, *argv, chdir: $project)
  reader.winsize = [rows, cols]
  out = +''
  pump = Thread.new do
    reader.each_char { |c| out << c }
  rescue Errno::EIO, IOError
    nil
  end
  yield(writer, pid) if block_given?
  code = Timeout.timeout(20) { Process.waitpid2(pid).last.exitstatus }
  pump.join(2)
  [out, code]
rescue Timeout::Error
  begin
    Process.kill('KILL', pid)
  rescue StandardError
    nil
  end
  ['TIMEOUT — the command hung', nil]
end

def start_server
  pid = Process.spawn(
    { 'PATH' => "#{FAKE_DIR}:#{ENV.fetch('PATH', '')}",
      'SPICE_TOKEN' => TOKEN,
      'SPICE_PORT' => HEALTH_PORT,
      'SPICE_STREAM_PORT' => STREAM_PORT },
    'ruby', SERVER, out: File::NULL, err: File::NULL
  )
  20.times do
    begin
      TCPSocket.new('127.0.0.1', STREAM_PORT.to_i).close
      return pid
    rescue StandardError
      sleep 0.25
    end
  end
  abort 'spice server did not come up'
end

File.chmod(0o755, "#{FAKE_DIR}/fake-heighliner")
File.symlink("#{FAKE_DIR}/fake-heighliner", "#{FAKE_DIR}/heighliner") unless File.exist?("#{FAKE_DIR}/heighliner")

server_pid = start_server
Dir.mktmpdir('spice-proj') do |dir|
  $project = dir

  puts 'output and exit codes'
  out, code = plain('show', 'hello')
  check('argv arrives', out, /argv=\[show hello\]/)
  check('cwd arrives', out, /cwd=#{Regexp.escape(dir)}/)
  check('real exit code', code, 7)
  check('no ^M for a non-tty client', out.include?("\r"), false)

  puts 'stdin'
  out, code = plain('readline', input: "typed-input\n")
  check('stdin forwarded', out, /got=typed-input/)
  check('exit code', code, 0)

  puts 'window size'
  out, = interactive('winsize', rows: 40, cols: 132)
  check('winsize reaches the command', out, /size=40 132/)

  puts 'interactive round trip'
  out, code = interactive('echoback') do |w, _pid|
    sleep 0.8
    w.write("ping\n")
    sleep 0.8
  end
  check('typed line echoed back', out, /you-said=ping/)
  check('exit code', code, 0)

  puts 'resize mid-run'
  out, = interactive('resizewatch', rows: 24, cols: 80) do |_w, pid|
    sleep 0.8
    Process.kill('WINCH', pid)
    sleep 1.5
  end
  check('command sees a size', out, /size=24 80/)

  puts '^C reaches the remote process group (this is what attach needs)'
  _out, code = interactive('sleeper') do |w, _pid|
    sleep 1
    w.write("\x03")
    sleep 0.5
  end
  check('dies by SIGINT instead of hanging', code, 130)

  puts 'failure paths'
  out, code = plain('show', env: { 'SPICE_TOKEN' => 'wrong' })
  check('bad token rejected', out, /bad or missing token/)
  check('bad token exits 1', code, 1)

  # Client and server share a filesystem here, so a genuinely-missing cwd has to
  # be produced by speaking the protocol directly.
  raw = TCPSocket.new('127.0.0.1', STREAM_PORT.to_i)
  raw.write("#{JSON.generate(token: TOKEN, argv: ['show'], cwd: '/no/such/place', tty: false)}\n")
  body = raw.read.to_s
  raw.close
  check('unmounted cwd explained', body.byteslice(5..).to_s, /does not exist on the spice server/)

  out, = plain('show', env: { 'SPICE_URL' => '' })
  check('missing SPICE_URL explained', out, /SPICE_URL is not set/)

  out, = plain('show', env: { 'SPICE_STREAM_PORT' => '7998' })
  check('server down explained', out, /cannot reach the spice server/)
end
ensure_kill = lambda do
  Process.kill('TERM', server_pid)
  Process.waitpid(server_pid)
rescue StandardError
  nil
end
ensure_kill.call
File.unlink("#{FAKE_DIR}/heighliner") if File.symlink?("#{FAKE_DIR}/heighliner")

puts
puts($failures.zero? ? 'ALL PASS' : "#{$failures} FAILURE(S)")
exit($failures.zero? ? 0 : 1)
