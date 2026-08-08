# frozen_string_literal: true

# The real client executable against a real server. Unit specs cannot reach the
# things that only exist in a whole process: raw mode, signal delivery, and the
# exit status a shell would see.
RSpec.describe Spice do
  describe '#run' do
    it 'runs the command and returns its output' do
      with_spice_server do |health, stream|
        out = IO.popen(client_env(health, stream), [client_path, 'show', 'hello'], err: %i[child out], &:read)

        expect(out).to include('argv=[show hello]')
      end
    end

    it 'runs the command in the directory the client was invoked from' do
      with_spice_server do |health, stream|
        dir = Dir.mktmpdir
        out = IO.popen(client_env(health, stream), [client_path, 'show'], chdir: dir, err: %i[child out], &:read)

        expect(out).to include("cwd=#{dir}")
      end
    end

    it 'exits with the code the command exited with' do
      with_spice_server do |health, stream|
        IO.popen(client_env(health, stream), [client_path, 'show'], err: %i[child out], &:read)

        expect($CHILD_STATUS.exitstatus).to eq(7)
      end
    end

    it 'leaves no carriage returns in output an agent captures' do
      with_spice_server do |health, stream|
        out = IO.popen(client_env(health, stream), [client_path, 'show'], err: %i[child out], &:read)

        expect(out).not_to include("\r")
      end
    end

    it 'forwards piped stdin' do
      with_spice_server do |health, stream|
        out = IO.popen(client_env(health, stream), [client_path, 'readline'], 'r+', err: %i[child out]) do |io|
          io.write("typed-input\n")
          io.close_write
          io.read
        end

        expect(out).to include('got=typed-input')
      end
    end

    it 'reports a rejected request in words rather than a backtrace' do
      with_spice_server do |health, stream|
        env = client_env(health, stream).merge('SPICE_TOKEN' => 'wrong')
        out = IO.popen(env, [client_path, 'show'], err: %i[child out], &:read)

        expect(out).to include('bad or missing token')
      end
    end

    it 'exits 1 when the request is rejected' do
      with_spice_server do |health, stream|
        env = client_env(health, stream).merge('SPICE_TOKEN' => 'wrong')
        IO.popen(env, [client_path, 'show'], err: %i[child out], &:read)

        expect($CHILD_STATUS.exitstatus).to eq(1)
      end
    end

    it 'explains an unreachable server instead of showing a socket error' do
      env = { 'SPICE_URL' => 'http://127.0.0.1', 'SPICE_STREAM_PORT' => free_port.to_s, 'SPICE_TOKEN' => 'x' }
      out = IO.popen(env, [client_path, 'show'], err: %i[child out], &:read)

      expect(out).to include('cannot reach the spice server')
    end

    it 'explains a missing SPICE_URL, which is the state of a sandbox with no spice' do
      out = IO.popen({ 'SPICE_URL' => nil }, [client_path, 'show'], err: %i[child out], &:read)

      expect(out).to include('SPICE_URL is not set')
    end

    it 'refuses to let a sandbox rewrite the shared configuration' do
      with_spice_server do |health, stream|
        out = IO.popen(client_env(health, stream), [client_path, 'set', 'http-suffix', 'evil.example'],
                       err: %i[child out], &:read)

        expect(out).to include('one for the user rather than spice')
      end
    end

    it 'exits non-zero when it refuses a command' do
      with_spice_server do |health, stream|
        IO.popen(client_env(health, stream), [client_path, 'set', 'http-suffix', 'x'], err: %i[child out], &:read)

        expect($CHILD_STATUS.exitstatus).to eq(1)
      end
    end

    it 'still allows reading the suffix, which an agent needs to reach the app' do
      with_spice_server do |health, stream|
        out = IO.popen(client_env(health, stream), [client_path, 'show', 'http-suffix'], err: %i[child out], &:read)

        expect(out).to include('argv=[show http-suffix]')
      end
    end

    it 'serves a health endpoint so sp status can ask whether it is alive' do
      with_spice_server do |health, _stream|
        body = Net::HTTP.get(URI("http://127.0.0.1:#{health}/health"))

        expect(JSON.parse(body)['ok']).to be(true)
      end
    end

    it 'reports on the health endpoint that it requires a token' do
      with_spice_server do |health, _stream|
        body = Net::HTTP.get(URI("http://127.0.0.1:#{health}/health"))

        expect(JSON.parse(body)['auth']).to be(true)
      end
    end
  end

  describe '#run with a terminal' do
    it 'gives the command the window size of the real terminal' do
      with_spice_server do |health, stream|
        reader, _writer, pid = PTY.spawn(client_env(health, stream), client_path, 'winsize')
        reader.winsize = [40, 132]
        out = read_until_eof(reader)
        Process.wait(pid)

        expect(out).to include('size=40 132')
      end
    end

    it 'echoes back what a user types interactively' do
      with_spice_server do |health, stream|
        reader, writer, pid = PTY.spawn(client_env(health, stream), client_path, 'echoback')
        sleep 0.5
        writer.write("ping\n")
        out = read_until_eof(reader)
        Process.wait(pid)

        expect(out).to include('you-said=ping')
      end
    end

    it 'sends ^C to the remote process group instead of dying locally' do
      with_spice_server do |health, stream|
        reader, writer, pid = PTY.spawn(client_env(health, stream), client_path, 'sleeper')
        sleep 1
        writer.write("\x03")
        read_until_eof(reader)
        _, status = Process.waitpid2(pid)

        expect(status.exitstatus).to eq(130)
      end
    end
  end
end
