package com.osmapps.framework.util;

import androidx.core.util.Consumer;

import java.io.*;
import java.nio.channels.FileChannel;

/***
 * @author jiangyulong@squarevalleytech.com <br/>
 * @date 2015-6-10 <br/>
 */

public final class IoUtils {

    public static final int KB = 1024;
    public static final int MB = KB * KB;

    public static int BUFFER_SIZE = 32 * KB;

    public static byte[] toBytes(InputStream input) throws IOException {
        if (input == null) {
            return null;
        }
        ByteArrayOutputStream swapStream = new ByteArrayOutputStream();
        byte[] buffer = new byte[BUFFER_SIZE];
        int n;
        while (-1 != (n = input.read(buffer))) {
            swapStream.write(buffer, 0, n);
        }
        return swapStream.toByteArray();
    }

    public static boolean copyStream(InputStream is, OutputStream os) throws IOException {
        return copyStream(is, os, null);
    }

    public static boolean copyStream(InputStream is, OutputStream os,
                                     Consumer<Integer> progressListener)
            throws IOException {
        final byte[] bytes = new byte[BUFFER_SIZE];
        int progress = 0;
        int count;
        while ((count = is.read(bytes, 0, BUFFER_SIZE)) != -1) {
            progress += count;
            if (progressListener != null) {
                progressListener.accept(progress);
            }
            os.write(bytes, 0, count);
        }
        os.flush();
        return true;
    }

    public static void closeSilently(Closeable closeable) {
        if (closeable != null) {
            try {
                closeable.close();
                closeable = null;
            } catch (Exception ignored) {
            }
        }
    }

    public static void copyFile(File s, File t) {
        FileInputStream fi = null;
        FileOutputStream fo = null;
        FileChannel in = null;
        FileChannel out = null;
        try {
            fi = new FileInputStream(s);
            fo = new FileOutputStream(t);
            in = fi.getChannel();
            out = fo.getChannel();
            in.transferTo(0, in.size(), out);
        } catch (IOException e) {
            e.printStackTrace();
        } finally {
            closeSilently(fi);
            closeSilently(fo);
            closeSilently(in);
            closeSilently(out);
        }
    }

    public static String copyFileToFolder(String destDir, String destName, String srcName) {
        String destPath = FileUtil.getAppStorageDirectory(destDir, true);
        File destFile = new File(new File(destPath), destName);
        IoUtils.copyFile(new File(srcName), destFile);
        return destFile.getAbsolutePath();
    }
}
