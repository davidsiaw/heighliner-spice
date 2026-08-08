# frozen_string_literal: true

# Drives a Session from the other end of a socket. Decoding is done by the
# production Channel, so there is no second implementation to drift.
module FrameClient
  ENDING = [SpiceWire::Frame::EXIT, SpiceWire::Frame::ERROR].freeze

  def frames_until_end(socket, timeout: 10)
    channel = SpiceWire::Channel.new(socket)
    frames = []
    while channel.wait_readable(timeout)
      batch = channel.receive_frames
      break if batch.nil?

      frames.concat(batch)
      break if frames.any? { |type, _| ENDING.include?(type) }
    end
    frames
  end

  def output_of(frames)
    frames.select { |type, _| type == SpiceWire::Frame::DATA }.map(&:last).join
  end

  def frame_payload(frames, wanted)
    frames.find { |type, _| type == wanted }&.last
  end
end
