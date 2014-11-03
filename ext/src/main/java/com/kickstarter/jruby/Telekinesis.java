package com.kickstarter.jruby;

import com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessorCheckpointer;
import com.amazonaws.services.kinesis.clientlibrary.lib.worker.KinesisClientLibConfiguration;
import com.amazonaws.services.kinesis.clientlibrary.lib.worker.Worker;
import com.amazonaws.services.kinesis.clientlibrary.types.ShutdownReason;
import com.amazonaws.services.kinesis.model.Record;

import java.util.List;

/**
 * A shim that makes it possible to use the Kinesis Client Library from JRuby.
 * Without the shim, {@code initialize} method in
 * {@link com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessor}
 * conflicts with the special {@code initialize} method in Ruby. The shim
 * interface renames {@code initialize} to {@code init}.
 * <p />
 *
 * For convenience a {@link #newWorker(KinesisClientLibConfiguration, IRecordProcessorFactory)}
 * method is provided, so you can use closure conversion in JRuby to specify an
 * {@link IRecordProcessorFactory}. For example
 *
 * <p />
 *
 * <pre>
 *     some_thing = ...
 *
 *     com.kickstarter.jruby.Telekinesis.new_worker(my_config) do
 *       MyRecordProcessor.new(some_thing, some_other_thing)
 *     end
 * </pre>
 */
public class Telekinesis {
    /**
     * Create a new KCL {@link Worker} that processes records using the given
     * {@link IRecordProcessorFactory}.
     */
    public static Worker newWorker(final KinesisClientLibConfiguration config, final IRecordProcessorFactory factory) {
        return new Worker(new com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessorFactory() {
            @Override
            public com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessor createProcessor() {
                return new RecordProcessorShim(factory.createProcessor());
            }
        }, config);
    }

    // ========================================================================
    /**
     * A shim that wraps a {@link IRecordProcessor} so it can get used by the KCL.
     */
    private static class RecordProcessorShim implements com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessor {
        private final IRecordProcessor underlying;

        public RecordProcessorShim(final IRecordProcessor underlying) { this.underlying = underlying; }

        @Override
        public void initialize(final String shardId) {
            underlying.init(shardId);
        }

        @Override
        public void processRecords(final List<Record> records, final IRecordProcessorCheckpointer checkpointer) {
            underlying.processRecords(records, checkpointer);
        }

        @Override
        public void shutdown(final IRecordProcessorCheckpointer checkpointer, final ShutdownReason reason) {
            underlying.shutdown(checkpointer, reason);
        }
    }

    /**
     * A parallel {@link com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessor}
     * that avoids naming conflicts with reserved words in Ruby.
     */
    public static interface IRecordProcessor {
        /**
         * @see com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessor#initialize(String)
         */
        void init(final String shardId);

        /**
         * @see com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessor#processRecords(List, IRecordProcessorCheckpointer)
         */
        void processRecords(List<Record> records, IRecordProcessorCheckpointer checkpointer);

        /**
         * @see com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessor#shutdown(IRecordProcessorCheckpointer, ShutdownReason)
         */
        void shutdown(IRecordProcessorCheckpointer checkpointer, ShutdownReason reason);
    }

    /**
     * A parallel {@link com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessorFactory}
     * for {@link IRecordProcessor}.
     */
    public static interface IRecordProcessorFactory {
        /**
         * @see com.amazonaws.services.kinesis.clientlibrary.interfaces.IRecordProcessorFactory#createProcessor()
         */
        IRecordProcessor createProcessor();
    }
}
