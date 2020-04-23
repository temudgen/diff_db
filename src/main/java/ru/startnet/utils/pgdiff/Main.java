/**
 * Copyright 2006 StartNet s.r.o.
 *
 * Distributed under MIT license
 */
package ru.startnet.utils.pgdiff;

import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;

/**
 * Compares two PostgreSQL dumps and outputs information about differences in
 * the database schemas.
 *
 * @author fordfrog
 */
public class Main {

    /**
     * APgDiff main method.
     *
     * @param args the command line arguments
     * @throws IOException 
     */
    public static void main(final String[] args)
            throws IOException {
        @SuppressWarnings("UseOfSystemOutOrSystemErr")
        final PrintWriter writer = new PrintWriter(System.out, true);
        final PgDiffArguments arguments = new PgDiffArguments();

        if (arguments.parse(writer, args)) {
          @SuppressWarnings("UseOfSystemOutOrSystemErr")
          final PrintWriter encodedWriter = new PrintWriter(
                  new OutputStreamWriter(
                  System.out, arguments.getOutCharsetName()));
          PgDiff.createDiff(encodedWriter, arguments);
          encodedWriter.close();
        }

        writer.close();
    }

    /**
     * Creates a new Main object.
     */
    private Main() {
    }
}
