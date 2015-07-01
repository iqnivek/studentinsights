module X2Importer
  # Any class using X2Importer should implement two methods:
  # export_file_name => string pointing to the name of the remote file to parse
  # import_row => function that describes how to handle each row; takes row as only argument

  attr_accessor :school

  def initialize(options = {})
    @school = options[:school]
  end

  def sftp_info_present?
    ENV['SIS_SFTP_HOST'].present? &&
    ENV['SIS_SFTP_USER'].present? &&
    ENV['SIS_SFTP_KEY'].present?
  end

  def connect_and_import
    if sftp_info_present?
      Net::SFTP.start(
        ENV['SIS_SFTP_HOST'],
        ENV['SIS_SFTP_USER'],
        key_data: ENV['SIS_SFTP_KEY'],
        keys_only: true,
        ) do |sftp|
        # For documentation see https://net-ssh.github.io/sftp/v2/api/
        file = sftp.download!(export_file_name).encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
        import(file)
      end
    else
      raise "SFTP information missing"
    end
  end

  def import(file)
    require 'csv'
    csv = CSV.new(file, headers: true, header_converters: :symbol, converters: lambda { |h| nil_converter(h) })
    number_of_rows, n = count_number_of_rows(file), 0 if Rails.env.development?

    csv.each do |row|
      print progress_bar(n, number_of_rows) if Rails.env.development?
      n += 1 if Rails.env.development?
      if @school.present?
        import_if_in_school_scope(row)
      else
        import_row row
      end
    end
    return csv
  end

  def nil_converter(field_value)
    if field_value == '\N'
      nil
    else
      field_value
    end
  end

  def import_if_in_school_scope(row)
    if @school.local_id == row[:school_local_id]
      import_row row
    end
  end

  def count_number_of_rows(file)
    CSV.parse(file).size
  end

  def progress_bar(n, length)
    fractional_progress = (n.to_f / length.to_f)
    percentage_progress = (fractional_progress * 100).to_i.to_s + "%"

    line_fill_part, line_empty_part = "", ""
    line_progress = (fractional_progress * 40).to_i

    line_progress.times { line_fill_part += "=" }
    (40 - line_progress).times { line_empty_part += " " }

    return "\r #{export_file_name} [#{line_fill_part}#{line_empty_part}] #{percentage_progress} (#{n} out of #{length})"
  end
end
