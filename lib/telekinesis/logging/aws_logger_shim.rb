java_import java.util.logging.Level
java_import java.util.logging.Handler

class RubyLoggerHandler < Handler
  SEVERITY = {
    # NOTE: No equivalent of FATAL
    Level::SEVERE => Logger::ERROR,
    Level::WARNING => Logger::WARN,
    Level::INFO => Logger::INFO,
    Level::CONFIG => Logger::INFO,
    Level::FINE=> Logger::DEBUG,
    Level::FINER=> Logger::DEBUG,
    Level::FINEST=> Logger::DEBUG,
  }

  def initialize(logger)
    @logger = logger
  end

  def close
    @logger.close
  end

  # Ruby's logger has no flush method.
  def flush; end

  def publish(log_record)
    message = if log_record.thrown.nil?
      log_record.message
    else
      "#{log_record.message}: #{log_record.thrown}"
    end
    @logger.add(SEVERITY[log_record.level], message, log_record.logger_name)
  end
end


