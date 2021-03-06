class Woody
  # Handles functions relating to deploying the Woody site
  module Deployer
    # Deploys the Woody site to S3
    def deploy
      puts "Deploying..."

      Dir.glob dir("output/**/*") do |item|
        next if File.directory? item
        item = undir item
        name = item[7..-1] # Remove "output/"
        next if name == "index.html" # These *must* be left until last
        next if name == "feed.xml"
        upload name, item
      end

      upload "index.html", "output/index.html"
      upload "feed.xml", "output/feed.xml"

      # Purge left over files
      purge_bucket
    end

    private


    # Deletes old objects from the S3 bucket
    # @param [Array] touchedfiles specifies the S3 objects to keep
    def purge_bucket
      bucket = AWS::S3::Bucket.find @bucketname
      prefix = @config['s3']['prefix']
      if prefix.nil?
        bucket.objects.each do |object|
          object.delete unless @s3touchedobjects.include? object.key
        end
      else
        bucket.objects.each do |object|
          if object.key.start_with? prefix # If using a prefix, don't delete anything outside of that 'subdirectory'
            object.delete unless @s3touchedobjects.include? object.key
          end
        end
      end
    end


    # Uploads a file to S3
    # Sets x-amz-meta-hash to hash generated by Woody::Generator.filehash and checks this
    # before uploading to avoid resending unchanged data
    # Prints notices to STDOUT
    # @param [String] objectname specifies the S3 object's key/name
    # @param [String] filepath specifies the path to the file to upload
    def upload(objectname, filepath)
      prefix = @config['s3']['prefix']
      unless prefix.nil?
        objectname = File.join(prefix, objectname)
      end

      filepath = dir(filepath)

      # Generate hash of file
      hash = filehash filepath
      @s3touchedobjects << objectname
      # Get hash of version already uploaded, if available.
      begin
        object = AWS::S3::S3Object.find objectname, @bucketname
        oldhash = object.metadata['hash']
      rescue AWS::S3::NoSuchKey
        # File not uploaded yet
        oldhash = nil
      end
      unless hash == oldhash
        # Don't reupload if file hasn't changed
        puts "#{objectname}: Uploading"
        AWS::S3::S3Object.store(objectname, open(filepath), @bucketname, access: :public_read, 'x-amz-meta-hash' => hash)
      else
        puts "#{objectname}: Not uploading, hasn't changed since last time."
      end
    end


    # Generates a hash of a file
    # Stored in S3 object metadata (x-amz-meta-hash) and used to avoid re-uploading unchanged files
    # @param  [String] filepath path to file
    # @return [String] hash of file
    def filehash(filepath)
      sha1 = Digest::SHA1.new
      File.open(filepath) do|file|
        buffer = ''
        # Read the file 512 bytes at a time
        while not file.eof
          file.read(512, buffer)
          sha1.update(buffer)
        end
      end
      return sha1.to_s
    end

  end
end