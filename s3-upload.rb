#!/usr/bin/env ruby

require 'optparse'

require 'rubygems'
require 'bundler/setup'

require 'aws-sdk'
require 'mime/types'

begin
  # Load env values first!
  require 'dotenv'
  Dotenv.load
rescue LoadError
  puts "No dot env; we must be in production."
end

class S3FolderUpload
  # Initialize the upload class
  #
  # folder_path - path to the folder that you want to upload
  # bucket - The bucket you want to upload to
  # aws_key - Your key generated by AWS defaults to the environemt setting AWS_KEY_ID
  # aws_secret - The secret generated by AWS
  #
  # Examples
  #   => uploader = S3FolderUpload.new("some_route/test_folder", 'your_bucket_name')
  #
  def initialize(folder_path, bucket, aws_key = ENV['AWS_ACCESS_KEY_ID'], aws_secret = ENV['AWS_SECRET_ACCESS_KEY'])
    @folder_path = folder_path
    @files       = Dir.glob "#{@folder_path}/**/{*,.*}"
    @connection  = Aws::S3::Resource.new(access_key_id: aws_key, secret_access_key: aws_secret, region: 'us-east-1')
    @s3_bucket   = @connection.bucket(bucket)
  end

  # public: Upload files from the folder to S3
  def upload!()
    file_number = 0

    total_files = @files.length

    @files.each do |file|
      file_number += 1

      print "\rUploading... [#{file_number}/#{total_files}]"

      next if File.directory? file

      # Get the path relative to containing directory
      path = file.gsub(/^#{@folder_path}\//, '')

      options = { :acl => "authenticated-read" }

      if MIME::Types.type_for(file).count > 0
        options[:content_type] = MIME::Types.type_for(file).first.to_str
      end

      @s3_bucket.object(path).upload_file(file, options)
    end

    puts "\rUpload complete!".ljust 80
  end

  # Delete files from S3 not included in path
  def cleanup!
    @s3_bucket.objects.each do |obj|
      if !@files.include? "#{@folder_path}/#{obj.key}"
        puts "Deleting #{obj.key}"
        obj.delete
      end
    end
  end
end

# Parse CLI Options
options = {
  :bucket     => ENV['BUCKET'],
  :upload_dir => '',
  :aws_key    => ENV['AWS_ACCESS_KEY_ID'],
  :aws_secret => ENV['AWS_SECRET_ACCESS_KEY']
}

parser = OptionParser.new do |opts|
  opts.on('-b', '--bucket=BUCKET', "S3 Bucket to deploy to (Required, default: \"#{options[:bucket]}\")") do |b|
    options[:bucket] = b
  end

  opts.on('-d', '--dir=DIRECTORY', "Directory to upload") do |d|
    options[:upload_dir] = d
  end

  opts.on('-k', '--aws_key=KEY', "AWS Upload Key (Required, default: \"#{options[:aws_key]}\")") do |k|
    options[:aws_key] = k
  end

  opts.on('-s', '--aws_secret=SECRET', "AWS Upload Secret (Required, default: \"#{options[:aws_secret]}\")") do |s|
    options[:aws_secret] = s
  end

  opts.on_tail('-h', '--help', 'Display this help') do
    puts opts
    exit
  end
end

parser.parse!

if options[:bucket] == nil || options[:aws_key] == nil || options[:aws_secret] == nil || options[:upload_dir] == ''
  puts parser
  exit
end

# Deploy
uploader = S3FolderUpload.new(options[:upload_dir], options[:bucket], options[:aws_key], options[:aws_secret])
uploader.upload!
uploader.cleanup!