package com.roana.litertsmoke;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;
import com.google.ai.edge.litert.Accelerator;
import com.google.ai.edge.litert.BuiltinNpuAcceleratorProvider;
import com.google.ai.edge.litert.CompiledModel;
import com.google.ai.edge.litert.Environment;
import com.google.ai.edge.litert.NpuCompatibilityChecker;
import com.google.ai.edge.litert.TensorBuffer;
import com.google.ai.edge.litert.TensorBufferRequirements;
import com.google.ai.edge.litert.TensorType;
import java.io.FileInputStream;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.Tensor;

public final class LiteRtSmokeActivity extends Activity {
    private static final String TAG = "RoanaLiteRt";
    private static final String EXTRA_DEBUG_LITERT_YOLO_SMOKE =
            "com.roana.app.extra.DEBUG_LITERT_YOLO_SMOKE";
    private static final String EXTRA_DEBUG_LITERT_DEPTH_SMOKE =
            "com.roana.app.extra.DEBUG_LITERT_DEPTH_SMOKE";
    private static final String EXTRA_DEBUG_LITERT_ACCELERATOR =
            "com.roana.app.extra.DEBUG_LITERT_ACCELERATOR";
    private static final String EXTRA_DEBUG_LITERT_TIMING_ITERATIONS =
            "com.roana.app.extra.DEBUG_LITERT_TIMING_ITERATIONS";
    private static final String YOLO_ASSET = "yolo11n-det-int8-smart.tflite";
    private static final String DEPTH_ASSET = "depth_anything_v2.tflite";
    private static final String INPUT_TENSOR_NAME = "input_0";
    private static final String OUTPUT_TENSOR_NAME = "output_0";
    private static final double NS_PER_MS = 1_000_000.0;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView status = new TextView(this);
        status.setText("LiteRT smoke running");
        status.setTextSize(18f);
        status.setPadding(32, 32, 32, 32);
        setContentView(status);

        boolean runYolo = getIntent().getBooleanExtra(EXTRA_DEBUG_LITERT_YOLO_SMOKE, false);
        boolean runDepth = getIntent().getBooleanExtra(EXTRA_DEBUG_LITERT_DEPTH_SMOKE, false);
        LiteRtAccelerator accelerator = LiteRtAccelerator.fromId(
                getIntent().getStringExtra(EXTRA_DEBUG_LITERT_ACCELERATOR));
        int timingIterations = getIntent().getIntExtra(EXTRA_DEBUG_LITERT_TIMING_ITERATIONS, 0);

        Thread smokeThread = new Thread(() -> {
            Log.i(TAG, "litert_model_smoke_matrix accelerator=" + accelerator.id
                    + " yolo=" + runYolo
                    + " depth=" + runDepth
                    + " timing_iterations=" + timingIterations);
            if (runYolo) {
                runModel(new ModelSpec("yolo", YOLO_ASSET), accelerator, timingIterations);
            }
            if (runDepth) {
                runModel(new ModelSpec("depth", DEPTH_ASSET), accelerator, timingIterations);
            }
        });
        smokeThread.setName("RoanaLiteRtModelSmoke");
        smokeThread.start();
    }

    private void runModel(
            ModelSpec spec,
            LiteRtAccelerator accelerator,
            int timingIterations
    ) {
        long startedNs = System.nanoTime();
        LoadedModel loadedModel;
        ModelMetadata metadata;
        Environment environment = null;
        CompiledModel compiledModel = null;
        try {
            loadedModel = loadModel(spec.asset);
            metadata = logTensorMetadata(spec, loadedModel);
            environment = createEnvironment(accelerator);
            Set<Accelerator> available = environment.getAvailableAccelerators();
            Log.i(TAG, "litert_backend requested=" + accelerator.id
                    + " model=" + spec.name
                    + " available=" + acceleratorSetToLog(available));

            if (accelerator == LiteRtAccelerator.NPU && !available.contains(Accelerator.NPU)) {
                Log.e(TAG, "litert_backend selected=unavailable model=" + spec.name
                        + " requested=" + accelerator.id
                        + " reason=npu_not_available");
                Log.e(TAG, "litert_model_smoke status=failed model=" + spec.name
                        + " asset=" + spec.asset
                        + " backend=unavailable reason=npu_not_available");
                return;
            }

            compiledModel = CompiledModel.create(
                    getAssets(),
                    spec.asset,
                    new CompiledModel.Options(accelerator.toLiteRtAccelerator()),
                    environment);
            logLiteRtTensorMetadata(spec, compiledModel);
            List<TensorBuffer> inputBuffers = compiledModel.createInputBuffers();
            List<TensorBuffer> outputBuffers = compiledModel.createOutputBuffers();
            fillZeroInputs(spec, metadata, inputBuffers);
            compiledModel.run(inputBuffers, outputBuffers);

            double loadMs = (System.nanoTime() - startedNs) / NS_PER_MS;
            BackendProof proof = backendProof(accelerator);
            if (proof.proven) {
                Log.i(TAG, "litert_backend selected=" + proof.backend + " model=" + spec.name);
            } else {
                Log.w(TAG, "litert_backend status=unproven model=" + spec.name
                        + " requested=" + accelerator.id
                        + " reason=" + proof.reason);
            }
            Log.i(TAG, "litert_model_smoke status=loaded model=" + spec.name
                    + " asset=" + spec.asset
                    + " backend=" + proof.backend
                    + " requested=" + accelerator.id
                    + " load_ms=" + format(loadMs));
            if (timingIterations > 0) {
                runTiming(
                        spec,
                        accelerator,
                        metadata,
                        compiledModel,
                        inputBuffers,
                        outputBuffers,
                        timingIterations);
            }
        } catch (UnsatisfiedLinkError error) {
            logFailure(spec, "missing", "runtime_missing:" + nullToEmpty(error.getMessage()), error);
        } catch (Exception error) {
            String reason = classifyFailure(error);
            String backend = reason.startsWith("runtime_missing") ? "missing" : "unproven";
            logFailure(spec, backend, reason, error);
        } finally {
            if (compiledModel != null) {
                compiledModel.close();
            }
            if (environment != null) {
                environment.close();
            }
        }
    }

    private Environment createEnvironment(LiteRtAccelerator accelerator) throws Exception {
        if (accelerator == LiteRtAccelerator.NPU) {
            return Environment.create(
                    new BuiltinNpuAcceleratorProvider(
                            this,
                            NpuCompatibilityChecker.Companion.getQualcomm()));
        }
        return Environment.create();
    }

    private void logLiteRtTensorMetadata(ModelSpec spec, CompiledModel compiledModel) {
        try {
            TensorType inputType = compiledModel.getInputTensorType(INPUT_TENSOR_NAME, null);
            TensorType outputType = compiledModel.getOutputTensorType(OUTPUT_TENSOR_NAME, null);
            TensorBufferRequirements inputRequirements =
                    compiledModel.getInputBufferRequirements(INPUT_TENSOR_NAME, null);
            TensorBufferRequirements outputRequirements =
                    compiledModel.getOutputBufferRequirements(OUTPUT_TENSOR_NAME, null);
            Log.i(TAG, "litert_tensor_metadata model=" + spec.name
                    + " input=" + tensorTypeToLog(inputType)
                    + " input_buffer=" + requirementsToLog(inputRequirements)
                    + " output=" + tensorTypeToLog(outputType)
                    + " output_buffer=" + requirementsToLog(outputRequirements));
        } catch (Exception error) {
            Log.w(TAG, "litert_tensor_metadata status=unavailable model=" + spec.name
                    + " reason=" + sanitize(nullToEmpty(error.getMessage())), error);
        }
    }

    private void runTiming(
            ModelSpec spec,
            LiteRtAccelerator accelerator,
            ModelMetadata metadata,
            CompiledModel compiledModel,
            List<TensorBuffer> inputBuffers,
            List<TensorBuffer> outputBuffers,
            int iterations
    ) throws Exception {
        double[] runTimesMs = new double[iterations];
        for (int index = 0; index < iterations; index += 1) {
            fillZeroInputs(spec, metadata, inputBuffers);
            long startedNs = System.nanoTime();
            compiledModel.run(inputBuffers, outputBuffers);
            runTimesMs[index] = (System.nanoTime() - startedNs) / NS_PER_MS;
        }
        double totalMs = 0.0;
        double minMs = Double.MAX_VALUE;
        double maxMs = 0.0;
        for (double runTimeMs : runTimesMs) {
            totalMs += runTimeMs;
            minMs = Math.min(minMs, runTimeMs);
            maxMs = Math.max(maxMs, runTimeMs);
        }
        Log.i(TAG, "litert_model_timing status=ok model=" + spec.name
                + " backend=" + accelerator.id
                + " iterations=" + iterations
                + " avg_ms=" + format(totalMs / iterations)
                + " min_ms=" + format(minMs)
                + " max_ms=" + format(maxMs));
    }

    private void fillZeroInputs(
            ModelSpec spec,
            ModelMetadata metadata,
            List<TensorBuffer> inputBuffers
    ) throws Exception {
        for (int index = 0; index < metadata.inputs.size(); index += 1) {
            TensorMetadata tensor = metadata.inputs.get(index);
            TensorBuffer inputBuffer = inputBuffers.get(index);
            switch (tensor.dataType) {
                case "FLOAT32":
                    inputBuffer.writeFloat(new float[tensor.elementCount]);
                    break;
                case "UINT8":
                case "INT8":
                    inputBuffer.writeInt8(new byte[tensor.elementCount]);
                    break;
                case "INT32":
                    inputBuffer.writeInt(new int[tensor.elementCount]);
                    break;
                case "INT64":
                    inputBuffer.writeLong(new long[tensor.elementCount]);
                    break;
                case "BOOL":
                    inputBuffer.writeBoolean(new boolean[tensor.elementCount]);
                    break;
                default:
                    throw new IllegalStateException(
                            "Unsupported LiteRT smoke input type "
                                    + tensor.dataType
                                    + " for "
                                    + spec.name);
            }
        }
    }

    private void logFailure(ModelSpec spec, String backend, String reason, Throwable error) {
        String sanitizedReason = sanitize(reason);
        String runtimeStatus = backend.equals("missing") || reason.startsWith("runtime_missing")
                ? "missing"
                : "unproven";
        if (reason.startsWith("model_rejected")) {
            Log.e(TAG, "litert_model status=rejected model=" + spec.name
                    + " reason=" + sanitizedReason, error);
        }
        Log.e(TAG, "litert_runtime status=" + runtimeStatus
                + " model=" + spec.name
                + " reason=" + sanitizedReason, error);
        Log.e(TAG, "litert_backend status=" + backend
                + " model=" + spec.name
                + " reason=" + sanitizedReason, error);
        Log.e(TAG, "litert_model_smoke status=failed model=" + spec.name
                + " asset=" + spec.asset
                + " backend=" + backend
                + " reason=" + sanitizedReason, error);
    }

    private String classifyFailure(Throwable error) {
        String message = nullToEmpty(error.getMessage());
        if (error instanceof IllegalArgumentException
                || containsIgnoreCase(message, "unsupported")
                || containsIgnoreCase(message, "invalid")) {
            return "model_rejected:" + message;
        }
        if (containsIgnoreCase(message, "not found")
                || containsIgnoreCase(message, "dlopen")
                || containsIgnoreCase(message, "library")) {
            return "runtime_missing:" + message;
        }
        return "backend_unproven:" + error.getClass().getSimpleName() + ":" + message;
    }

    private ModelMetadata logTensorMetadata(ModelSpec spec, LoadedModel model) throws Exception {
        try (Interpreter interpreter = new Interpreter(
                model.buffer,
                new Interpreter.Options().setNumThreads(1).setUseXNNPACK(true))) {
            ModelMetadata metadata = new ModelMetadata();
            for (int index = 0; index < interpreter.getInputTensorCount(); index += 1) {
                metadata.inputs.add(TensorMetadata.from(interpreter.getInputTensor(index)));
            }
            for (int index = 0; index < interpreter.getOutputTensorCount(); index += 1) {
                metadata.outputs.add(TensorMetadata.from(interpreter.getOutputTensor(index)));
            }
            Log.i(TAG, "litert_model_metadata model=" + spec.name
                    + " asset=" + spec.asset
                    + " bytes=" + model.byteCount
                    + " inputs=" + tensorMetadataListToLog(metadata.inputs)
                    + " outputs=" + tensorMetadataListToLog(metadata.outputs));
            return metadata;
        } catch (Exception error) {
            Log.e(TAG, "litert_model_metadata status=failed model=" + spec.name
                    + " asset=" + spec.asset
                    + " error=" + error.getClass().getSimpleName()
                    + " message=" + sanitize(nullToEmpty(error.getMessage())), error);
            throw error;
        }
    }

    private LoadedModel loadModel(String asset) throws Exception {
        try (android.content.res.AssetFileDescriptor descriptor = getAssets().openFd(asset);
             FileInputStream inputStream = new FileInputStream(descriptor.getFileDescriptor());
             FileChannel channel = inputStream.getChannel()) {
            return new LoadedModel(
                    channel.map(
                            FileChannel.MapMode.READ_ONLY,
                            descriptor.getStartOffset(),
                            descriptor.getDeclaredLength()),
                    descriptor.getDeclaredLength());
        }
    }

    private BackendProof backendProof(LiteRtAccelerator accelerator) {
        if (accelerator == LiteRtAccelerator.CPU) {
            return new BackendProof(true, "cpu", "explicit_cpu_request");
        }
        return new BackendProof(
                false,
                "unproven",
                "compiledmodel_api_does_not_expose_actual_backend");
    }

    private String tensorTypeToLog(TensorType type) {
        TensorType.Layout layout = type.getLayout();
        String dimensions = layout == null ? "unknown" : layout.getDimensions().toString();
        return type.getElementType().name() + dimensions;
    }

    private String requirementsToLog(TensorBufferRequirements requirements) {
        return "size=" + requirements.getBufferSize()
                + " types=" + requirements.getSupportedTypes();
    }

    private String tensorMetadataListToLog(List<TensorMetadata> metadata) {
        StringBuilder builder = new StringBuilder();
        for (int index = 0; index < metadata.size(); index += 1) {
            if (index > 0) {
                builder.append(';');
            }
            builder.append(metadata.get(index).toLog());
        }
        return builder.toString();
    }

    private String acceleratorSetToLog(Set<Accelerator> accelerators) {
        StringBuilder builder = new StringBuilder();
        int index = 0;
        for (Accelerator accelerator : accelerators) {
            if (index > 0) {
                builder.append(',');
            }
            builder.append(accelerator.name().toLowerCase(Locale.US));
            index += 1;
        }
        return builder.toString();
    }

    private String format(double value) {
        return String.format(Locale.US, "%.2f", value);
    }

    private static boolean containsIgnoreCase(String haystack, String needle) {
        return haystack.toLowerCase(Locale.US).contains(needle.toLowerCase(Locale.US));
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

    private static String sanitize(String value) {
        return value.replace('\n', '_')
                .replace('\r', '_')
                .replace(' ', '_');
    }

    private enum LiteRtAccelerator {
        NPU("npu"),
        GPU("gpu"),
        CPU("cpu");

        final String id;

        LiteRtAccelerator(String id) {
            this.id = id;
        }

        Accelerator toLiteRtAccelerator() {
            switch (this) {
                case GPU:
                    return Accelerator.GPU;
                case CPU:
                    return Accelerator.CPU;
                case NPU:
                default:
                    return Accelerator.NPU;
            }
        }

        static LiteRtAccelerator fromId(String id) {
            if (id == null) {
                return NPU;
            }
            for (LiteRtAccelerator accelerator : values()) {
                if (accelerator.id.equals(id.toLowerCase(Locale.US))) {
                    return accelerator;
                }
            }
            return NPU;
        }
    }

    private static final class ModelSpec {
        final String name;
        final String asset;

        ModelSpec(String name, String asset) {
            this.name = name;
            this.asset = asset;
        }
    }

    private static final class LoadedModel {
        final MappedByteBuffer buffer;
        final long byteCount;

        LoadedModel(MappedByteBuffer buffer, long byteCount) {
            this.buffer = buffer;
            this.byteCount = byteCount;
        }
    }

    private static final class ModelMetadata {
        final List<TensorMetadata> inputs = new ArrayList<>();
        final List<TensorMetadata> outputs = new ArrayList<>();
    }

    private static final class TensorMetadata {
        final int index;
        final String dataType;
        final int[] shape;
        final float scale;
        final int zeroPoint;
        final int elementCount;

        TensorMetadata(int index, String dataType, int[] shape, float scale, int zeroPoint) {
            this.index = index;
            this.dataType = dataType;
            this.shape = shape;
            this.scale = scale;
            this.zeroPoint = zeroPoint;
            this.elementCount = product(shape);
        }

        static TensorMetadata from(Tensor tensor) {
            Tensor.QuantizationParams quantization = tensor.quantizationParams();
            return new TensorMetadata(
                    tensor.index(),
                    tensor.dataType().name(),
                    tensor.shape(),
                    quantization.getScale(),
                    quantization.getZeroPoint());
        }

        String toLog() {
            return index
                    + ":"
                    + dataType
                    + java.util.Arrays.toString(shape)
                    + ":q="
                    + String.format(Locale.US, "%.8f", scale)
                    + ","
                    + zeroPoint;
        }

        private static int product(int[] values) {
            int result = 1;
            for (int value : values) {
                result *= value;
            }
            return result;
        }
    }

    private static final class BackendProof {
        final boolean proven;
        final String backend;
        final String reason;

        BackendProof(boolean proven, String backend, String reason) {
            this.proven = proven;
            this.backend = backend;
            this.reason = reason;
        }
    }
}
