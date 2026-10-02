package io.streaming.uc1;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericDatumReader;
import org.apache.avro.generic.GenericDatumWriter;
import org.apache.avro.generic.GenericRecord;
import org.apache.avro.io.BinaryDecoder;
import org.apache.avro.io.BinaryEncoder;
import org.apache.avro.io.DecoderFactory;
import org.apache.avro.io.EncoderFactory;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Deterministic consumer read matrix for UC1.
 *
 * <p>For every writer schema (v1, v2), every declared consumer and every reader
 * schema the consumer may run (v1 = not yet upgraded, v2 = upgraded), it encodes
 * the sample events with the writer schema, decodes them with Avro schema
 * resolution using the reader schema (what the Apicurio Avro deserializer does
 * when a reader schema is configured), and then applies the consumer's contract:
 * every required field must be present and non-null.
 *
 * <p>Usage: ReadMatrix &lt;v1.avsc&gt; &lt;v2.avsc&gt; &lt;samples-v1.jsonl&gt;
 * &lt;samples-v2.jsonl&gt; &lt;consumers.json&gt;
 *
 * <p>Exit code: 0 if every verifiable cell passes, 1 if any cell fails,
 * 3 if no cell fails but some cells could not be verified.
 */
public final class ReadMatrix {

    private ReadMatrix() {
    }

    public static void main(String[] args) throws IOException {
        if (args.length != 5) {
            System.err.println("usage: ReadMatrix <v1.avsc> <v2.avsc> <samples-v1.jsonl> "
                    + "<samples-v2.jsonl> <consumers.json>");
            System.exit(2);
        }
        Map<String, Schema> schemas = new LinkedHashMap<>();
        schemas.put("v1", new Schema.Parser().parse(Path.of(args[0]).toFile()));
        schemas.put("v2", new Schema.Parser().parse(Path.of(args[1]).toFile()));
        Map<String, List<String>> samples = Map.of(
                "v1", readLines(Path.of(args[2])),
                "v2", readLines(Path.of(args[3])));
        JsonNode inventory = new ObjectMapper().readTree(Path.of(args[4]).toFile());

        int failures = 0;
        int unverified = 0;
        System.out.printf("%-8s %-14s %-8s %-11s %s%n", "WRITER", "CONSUMER", "READER", "RESULT", "DETAIL");
        for (String writer : schemas.keySet()) {
            for (JsonNode consumer : inventory.get("consumers")) {
                String name = consumer.get("name").asText();
                String current = consumer.path("currentReaderSchema").asText("unknown");
                List<String> required = requiredFields(consumer);
                for (String reader : schemas.keySet()) {
                    String readerLabel = reader + (reader.equals(current) ? "*" : "");
                    Cell cell = evaluate(schemas.get(writer), schemas.get(reader),
                            samples.get(writer), required);
                    if (cell.result.equals("FAIL")) {
                        failures++;
                    } else if (cell.result.equals("UNVERIFIED")) {
                        unverified++;
                    }
                    System.out.printf("%-8s %-14s %-8s %-11s %s%n", writer, name, readerLabel,
                            cell.result, cell.detail);
                }
            }
        }
        System.out.println();
        System.out.println("* = reader schema the consumer currently runs (per inventory).");
        System.out.printf("summary: %d failed, %d unverified%n", failures, unverified);
        System.exit(failures > 0 ? 1 : unverified > 0 ? 3 : 0);
    }

    private static Cell evaluate(Schema writer, Schema reader, List<String> samples, List<String> required) {
        int index = 0;
        for (String json : samples) {
            index++;
            GenericRecord record;
            try {
                record = roundTrip(writer, reader, json);
            } catch (IOException | RuntimeException e) {
                return new Cell("FAIL", "sample #" + index + " not decodable: " + e.getMessage());
            }
            if (required == null) {
                continue;
            }
            for (String field : required) {
                if (reader.getField(field) == null) {
                    return new Cell("FAIL", "required field '" + field + "' absent from reader schema");
                }
                if (record.get(field) == null) {
                    return new Cell("FAIL", "sample #" + index + ": required field '" + field + "' is null");
                }
            }
        }
        if (required == null) {
            return new Cell("UNVERIFIED", "decoded " + samples.size() + " samples; consumer contract unknown");
        }
        return new Cell("PASS", "decoded " + samples.size() + " samples; contract " + required + " satisfied");
    }

    private static GenericRecord roundTrip(Schema writer, Schema reader, String json) throws IOException {
        GenericDatumReader<GenericRecord> jsonReader = new GenericDatumReader<>(writer);
        GenericRecord written = jsonReader.read(null, DecoderFactory.get().jsonDecoder(writer, json));

        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        BinaryEncoder encoder = EncoderFactory.get().binaryEncoder(bytes, null);
        new GenericDatumWriter<GenericRecord>(writer).write(written, encoder);
        encoder.flush();

        BinaryDecoder decoder = DecoderFactory.get().binaryDecoder(bytes.toByteArray(), null);
        return new GenericDatumReader<GenericRecord>(writer, reader).read(null, decoder);
    }

    private static List<String> requiredFields(JsonNode consumer) {
        JsonNode node = consumer.get("requiredFields");
        if (node == null || !node.isArray()) {
            return null;
        }
        List<String> fields = new ArrayList<>();
        node.forEach(f -> fields.add(f.asText()));
        return fields;
    }

    private static List<String> readLines(Path path) throws IOException {
        return Files.readAllLines(path).stream().filter(l -> !l.isBlank()).toList();
    }

    private record Cell(String result, String detail) {
    }
}
