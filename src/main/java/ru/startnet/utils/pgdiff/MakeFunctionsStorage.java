package ru.startnet.utils.pgdiff;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileWriter;
import java.io.IOException;

import ru.startnet.utils.pgdiff.schema.PgDatabase;
import ru.startnet.utils.pgdiff.schema.PgFunction;
import ru.startnet.utils.pgdiff.schema.PgFunction.Argument;
import ru.startnet.utils.pgdiff.schema.PgSchema;

public class MakeFunctionsStorage {
  
  public static MakeFunctionsStorage getInstance = new MakeFunctionsStorage();
  
  public void dumpAllFunctions(File pathStorage, PgDatabase newDatabase) throws IOException {
    if (!pathStorage.exists()) {
        if (!pathStorage.mkdirs())
          return;
    } else {
      deleteDirectory(pathStorage);
      pathStorage.mkdirs();
    }
    
    for (PgSchema schema : newDatabase.getSchemas()) {
      try {
        createFolderSchema(schema, pathStorage);
      } catch (IOException e) {
        throw e;
      }
    }
  }
  
  private void createFolderSchema(PgSchema schema, File pathStorage) throws IOException {
    File pathSchema = new File(pathStorage.getCanonicalPath() + "/" + schema.getName());
    if (schema.getFunctions() != null && schema.getFunctions().size() > 0) {
      pathSchema.mkdir();
      for (PgFunction function : schema.getFunctions()) {
        createFile(function, pathSchema.getCanonicalPath());
      }
    }
  }
  
  private void createFile(PgFunction function, String pathSchema) throws IOException {
    StringBuilder sb = new StringBuilder();
    for (Argument arg : function.getArguments()) {
      sb.append("_" + arg.getDataType());
    }
    BufferedWriter writer  = new BufferedWriter(new FileWriter(pathSchema + "/" + function.getName() + sb.toString() + ".sql"));
    try {
      writer.write(function.getCreationSQL());
    } catch (IOException e) {
      throw e;
    } finally {
      writer.close();
    }
  }
 
  public void cleanDirectory(final File directory) throws IOException {
    final File[] files = verifiedListFiles(directory);

    IOException exception = null;
    for (final File file : files) {
        try {
            forceDelete(file);
        } catch (final IOException ioe) {
            exception = ioe;
        }
    }

    if (null != exception) {
        throw exception;
    }
  }
  
  private File[] verifiedListFiles(File directory) throws IOException {
    if (!directory.exists()) {
        final String message = directory + " does not exist";
        throw new IllegalArgumentException(message);
    }

    if (!directory.isDirectory()) {
        final String message = directory + " is not a directory";
        throw new IllegalArgumentException(message);
    }

    final File[] files = directory.listFiles();
    if (files == null) {  // null if security restricted
        throw new IOException("Failed to list contents of " + directory);
    }
    return files;
  }
  
  public void forceDelete(final File file) throws IOException {
    if (file.isDirectory()) {
        deleteDirectory(file);
    } else {
        final boolean filePresent = file.exists();
        if (!file.delete()) {
            if (!filePresent) {
                throw new FileNotFoundException("File does not exist: " + file);
            }
            final String message =
                    "Unable to delete file: " + file;
            throw new IOException(message);
        }
    }
  }
  
  public void deleteDirectory(final File directory) throws IOException {
    if (!directory.exists()) {
        return;
    }

    cleanDirectory(directory);

    if (!directory.delete()) {
        final String message =
                "Unable to delete directory " + directory + ".";
        throw new IOException(message);
    }
  }

  
}