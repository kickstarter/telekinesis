java_import java.util.logging.Level
java_import java.util.logging.Handler

class AwsLoggerShim < Handler
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

  def close
    # Never actually close the underlying Ruby logger, since by default it's
    # a shared instance across the whole lib. Noop.
  end

  def flush
    # Logger has no flush method. Noop.
  end

  def publish(log_record)
    Telekinesis.aws_logger.add(SEVERITY[log_record.level],
                               log_record.logger_name,
                               log_record.message)
  end
end


