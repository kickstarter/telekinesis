java_import java.util.logging.Level
java_import java.util.logging.Handler

class NoopLoggerShim < Handler
  def close; end
  def flush; end
  def publish(log_record); end
end
