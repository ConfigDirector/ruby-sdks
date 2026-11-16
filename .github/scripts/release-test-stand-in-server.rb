# frozen_string_literal: true

require "fileutils"
require "socket"

directory = ARGV.fetch(0)
answers_directory = File.join(directory, "answers")
requests_directory = File.join(directory, "requests")

server = TCPServer.new("127.0.0.1", 0)
File.write(File.join(directory, "port.tmp"), server.addr[1].to_s)
File.rename(File.join(directory, "port.tmp"), File.join(directory, "port"))

loop do
  client = server.accept
  request_method, target, = client.gets.to_s.split
  headers = []
  while (line = client.gets) && line != "\r\n"
    headers << line.chomp
  end
  content_length = headers.filter_map { |header| header[/\Acontent-length:\s*(\d+)\z/i, 1] }.first.to_i
  body = content_length.zero? ? "" : client.read(content_length)

  exchange = "#{request_method}#{target.to_s.split("?").first.tr("/", "_")}"
  FileUtils.mkdir_p(requests_directory)
  File.write(File.join(requests_directory, "#{exchange}.target"), "#{target}\n")
  File.write(File.join(requests_directory, "#{exchange}.headers"), "#{headers.join("\n")}\n")
  File.binwrite(File.join(requests_directory, "#{exchange}.body"), body)

  answer_file = File.join(answers_directory, exchange)
  status, answer = File.exist?(answer_file) ? File.read(answer_file).split("\n", 2) : ["404", "No answer scripted."]
  answer = answer.to_s
  client.write(
    "HTTP/1.1 #{status} Scripted\r\nContent-Type: application/json\r\n" \
    "Content-Length: #{answer.bytesize}\r\nConnection: close\r\n\r\n#{answer}"
  )
  client.close
end
