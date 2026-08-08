# frozen_string_literal: true

# Boots the real server.rb as a separate process, against the fake heighliner.
module SpiceServer
  TOKEN = 'integration-token'

  def with_spice_server
    health = free_port
    stream = free_port
    pid = spawn_server(health, stream)
    wait_for_port(stream)
    yield(health, stream)
  ensure
    Process.kill('TERM', pid)
    Process.wait(pid)
  end

  def spawn_server(health, stream)
    Process.spawn(
      { 'PATH' => "#{FAKE_BIN}:#{ENV.fetch('PATH', '')}", 'SPICE_TOKEN' => TOKEN,
        'SPICE_PORT' => health.to_s, 'SPICE_STREAM_PORT' => stream.to_s },
      'ruby', "#{SPICE_ROOT}/server.rb", out: File::NULL, err: File::NULL
    )
  end

  # The real executable, exactly as a sandbox invokes it.
  def client_env(health, stream)
    { 'SPICE_URL' => "http://127.0.0.1:#{health}", 'SPICE_STREAM_PORT' => stream.to_s,
      'SPICE_TOKEN' => TOKEN }
  end

  def client_path
    "#{SPICE_ROOT}/client/heighliner"
  end

  def free_port
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end

  def wait_for_port(port)
    40.times do
      TCPSocket.new('127.0.0.1', port).close
      return true
    rescue SystemCallError
      sleep 0.1
    end
    raise 'spice server did not start'
  end
end
