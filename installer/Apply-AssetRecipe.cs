using System;
using System.IO;
using System.IO.Compression;
using System.Collections;
using System.Collections.Generic;
using System.Web.Script.Serialization;

public static class RanchersAssetRecipe {
    static void Copy(Stream input, Stream output, long count, byte[] buffer) {
        while(count > 0) {
            int read = input.Read(buffer, 0, (int)Math.Min(buffer.Length, count));
            if(read <= 0) throw new EndOfStreamException();
            output.Write(buffer, 0, read); count -= read;
        }
    }
    public static void Apply(string source, string payload, string recipe, string output, long expectedSize) {
        var serializer = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue };
        var document = serializer.Deserialize<Dictionary<string,object>>(File.ReadAllText(recipe));
        byte[] buffer = new byte[8*1024*1024];
        using(var src = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.None))
        using(var patch = new FileStream(payload, FileMode.Open, FileAccess.Read, FileShare.Read))
        using(var dst = new FileStream(output, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
            foreach(var item in (IEnumerable)document["operations"]) {
                var operation = (Dictionary<string,object>)item;
                long offset = Convert.ToInt64(operation["offset"]);
                long count = Convert.ToInt64(operation["length"]);
                if(offset < 0 || count < 0 || count > expectedSize - dst.Position) throw new InvalidDataException("Invalid patch range.");
                if((string)operation["kind"] == "copy") {
                    if(count > src.Length-offset) throw new InvalidDataException("Invalid source range.");
                    src.Position = offset; Copy(src, dst, count, buffer);
                } else if((string)operation["kind"] == "deflate") {
                    int packed = Convert.ToInt32(operation["compressed_length"]);
                    if(packed < 0 || packed > patch.Length-offset) throw new InvalidDataException("Invalid payload range.");
                    byte[] bytes = new byte[packed]; patch.Position = offset;
                    int total = 0;
                    while(total < packed) {
                        int read = patch.Read(bytes, total, packed-total);
                        if(read == 0) throw new EndOfStreamException();
                        total += read;
                    }
                    using(var memory = new MemoryStream(bytes))
                    using(var inflater = new DeflateStream(memory, CompressionMode.Decompress)) {
                        Copy(inflater, dst, count, buffer);
                        if(inflater.ReadByte() != -1) throw new InvalidDataException("Unexpected expanded data.");
                    }
                } else throw new InvalidDataException("Unknown patch operation.");
            }
            if(dst.Length != expectedSize) throw new InvalidDataException("Output size differs.");
            dst.Flush(true);
        }
    }
}
