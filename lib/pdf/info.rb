require 'date' unless defined? DateTime
require 'pdf/info/exceptions'

module PDF
  class Info
    @@command_path = "pdfinfo"

    def self.command_path=(path)
      @@command_path = path
    end

    def self.command_path
      @@command_path
    end

    def initialize(pdf_path)
      @pdf_path = pdf_path
    end

    def command
      require "open3"
      output = `#{self.class.command_path} -enc UTF-8 "#{@pdf_path}" -f 1 -l -1`
      output, erroroutput,exit_code = Open3.capture3("#{self.class.command_path} -enc UTF-8 '#{@pdf_path}' -f 1 -l -1")
      case exit_code.exitstatus
      when 0 || nil
        if !output.valid_encoding?
          # It's already UTF-8, so we need to convert to UTF-16 and back to
          # force the bad characters to be replaced.
          output.encode!('UTF-16', :undef => :replace, :invalid => :replace, :replace => "")
          output.encode!('UTF-8')
        end
        return output
      when 1 
        if erroroutput.include?("Command Line Error: Incorrect password")
          raise PDF::Info::IncorrectPasswordExitError.new
        end
      else
        exit_error = PDF::Info::UnexpectedExitError.new
        exit_error.exit_code = exit_code.exitstatus
        raise exit_error
      end
    end

    def metadata
      begin
        process_output(command)
      rescue UnexpectedExitError => e
        case e.exit_code
        when 1
          raise FileError
        when 2
          raise OutputError
        when 3
          raise BadPermissionsError
        else
          raise UnknownError
        end
      end
    end

    def process_output(output)
      rows = output.split("\n")
      metadata = {}
      rows.each do |row|
        pair = row.split(':', 2)
        pair.map!(&:strip)

        case pair.first
        when "Pages"
          metadata[:page_count] = pair.last.to_i
        when "Encrypted"
          if pair.last.size > 3 # more Infos then yes
            metadata[:encrypted] = true
            # Example: yes (print:no copy:no change:no addNotes:no)
            rightsString = pair.last[5..-2]
            rights = rightsString.split(" ")
            for right in rights
              pair = right.split(":")
              metadata[pair.first.to_sym] = pair.last == 'yes'
            end
          else
            metadata[:encrypted] = pair.last == 'yes' # just yes or no
            # If there are no information available, then it is allowed
            metadata[:print] = true if metadata[:print].nil? 
            metadata[:copy] = true if metadata[:copy].nil? 
            metadata[:change] = true if metadata[:change].nil?
            metadata[:addNotes] = true if metadata[:addNotes].nil?
          end
        when "Optimized"
          metadata[:optimized] = pair.last == 'yes'
        when "Tagged"
          metadata[:tagged] = pair.last == 'yes'
        when "PDF version"
          metadata[:version] = pair.last.to_f
        when "CreationDate"
          creation_date = parse_datetime(pair.last)
          metadata[:creation_date] = creation_date if creation_date
        when "ModDate"
          modification_date = parse_datetime(pair.last)
          metadata[:modification_date] = modification_date if modification_date
        when /^Page.*size$/
          metadata[:pages] ||= []
          p = Hash.new
          p[:number] = pair.first[/\d+/].to_i
          format = pair.last.scan(/(\d+\.?\d+)/)
          p[:width] = format[0].first.to_i
          p[:height] = format[1].first.to_i
          p[:format] = pair.last.scan(/\((.+)\)/).first[0].to_s
          metadata[:pages] << p
          metadata[:format] = pair.last.scan(/.*\(\w+\)$/).to_s
        when /^Page.*rot$/
          element = metadata[:pages][pair.first[/\d+/].to_i - 1]
          element[:rotate] = pair.last[/\d+/].to_i
        when String
          metadata[pair.first.downcase.tr(" ", "_").to_sym] = pair.last.to_s.strip
        end
      end

      metadata
    end

    private

    def parse_datetime(value)
      DateTime.parse(value)
    rescue
      begin
        DateTime.strptime(value, '%m/%d/%Y %k:%M:%S')
      rescue
        nil
      end
    end

  end
end
