package com.kickstarter.jruby;


import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.kinesis.clientlibrary.lib.worker.KinesisClientLibConfiguration;
import com.amazonaws.services.kinesis.clientlibrary.lib.worker.Worker;
import com.amazonaws.services.kinesis.clientlibrary.types.InitializationInput;
import com.amazonaws.services.kinesis.clientlibrary.types.ProcessRecordsInput;
import com.amazonaws.services.kinesis.clientlibrary.types.ShutdownInput;

import java.util.concurrent.ExecutorService;

/**
 * A shim that makes it possible to use the Kinesis Client Library from JRuby.
 * Without the shim, {@code initialize} method in
 * {@link com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessor}
 * conflicts with the special {@code initialize} method in Ruby. The shim
 * interface renames {@code initialize} to {@code init}.
 * <p />
 *
 * For convenience a {@link #newWorker(KinesisClientLibConfiguration, ExecutorService, IRecordProcessorFactory)}
 * method is provided, so you can use closure conversion in JRuby to specify an
 * {@link IRecordProcessorFactory}. For example
 *
 * <p />
 *
 * <pre>
 *     executor = config[:executor] || nil
 *
 *     com.kickstarter.jruby.Telekinesis.new_worker(my_config, executor) do
 *       MyRecordProcessor.new(some_thing, some_other_thing)
 *     end
 * </pre>
 */
public class Telekinesis {
    /**
     * Create a new KCL {@link Worker} that processes records using the given
     * {@link ExecutorService}, {@link IRecordProcessorFactory}, and
     * {@link AmazonDynamoDB}.
     */
    public static Worker newWorker(final KinesisClientLibConfiguration config,
                                   final ExecutorService executor,
                                   final AmazonDynamoDB dynamoClient,
                                   final IRecordProcessorFactory factory) {
        com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessorFactory v2Factory = new com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessorFactory() {
            @Override
            public com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessor createProcessor() {
                return new RecordProcessorShim(factory.createProcessor());
            }
        };

        return new Worker.Builder()
                .recordProcessorFactory(v2Factory)
                .config(config)
                .execService(executor) // NOTE: .execService(null) is a no-op
                .dynamoDBClient(dynamoClient)
                .build();
    }

    // ========================================================================
    /**
     * A shim that wraps a {@link IRecordProcessor} so it can get used by the KCL.
     */
    private static class RecordProcessorShim implements com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessor {
        private final IRecordProcessor underlying;

        public RecordProcessorShim(final IRecordProcessor underlying) { this.underlying = underlying; }

        @Override
        public void initialize(final InitializationInput initializationInput) {
            underlying.init(initializationInput);
        }

        @Override
        public void processRecords(final ProcessRecordsInput processRecordsInput) {
            underlying.processRecords(processRecordsInput);
        }

        @Override
        public void shutdown(final ShutdownInput shutdownInput) {
            underlying.shutdown(shutdownInput);
        }
    }

    /**
     * A parallel {@link com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessor}
     * that avoids naming conflicts with reserved words in Ruby.
     */
    public static interface IRecordProcessor {
        /**
         * @see com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessor#initialize(InitializationInput)
         */
        void init(InitializationInput initializationInput);

        /**
         * @see com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessor#processRecords(ProcessRecordsInput)
         */
        void processRecords(ProcessRecordsInput processRecordsInput);

        /**
         * @see com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessor#shutdown(ShutdownInput)
         */
        void shutdown(ShutdownInput shutdownInput);
    }

    /**
     * A parallel {@link com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessorFactory}
     * for {@link IRecordProcessor}.
     */
    public static interface IRecordProcessorFactory {
        /**
         * @see com.amazonaws.services.kinesis.clientlibrary.interfaces.v2.IRecordProcessorFactory#createProcessor()
         */
        IRecordProcessor createProcessor();
    }
}
