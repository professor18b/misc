package com.osmapps.framework.util;

import android.net.Uri;
import com.osmapps.framework.JkFrame;

import java.io.*;

/**
 * Utility for file operation.
 *
 * @author wlei 2012-5-12
 */
public class FileUtil {

    public static final String VIDEO_EXTENSION = ".mp4";
    public static final String IMAGE_EXTENSION = ".jpg";

    /**
     * @see #getAppStorageDirectory(String)
     */
    public static final String getAppStorageDirectory() {
        return getAppStorageDirectory(null);
    }

    /**
     * Returns directory of application for storage. <br/>
     * Returns <code>null</code> when:
     * <p>
     * <li>SDCard is not mounted
     * <li>appFolder is not exist.
     * </p>
     *
     * @param subDir subdirectory of appFolder.
     */
    public static final String getAppStorageDirectory(String subDir) {
        return getAppStorageDirectory(subDir, true);
    }

    public static final String getAppStorageDirectory(String subDir, boolean needCreateDir) {
        File cacheDir = JkFrame.getApplication().getExternalCacheDir();
        if (cacheDir == null) {
            cacheDir = JkFrame.getApplication().getCacheDir();
        }
        return getOrCreateAppStorageDirctory(cacheDir, subDir, needCreateDir);
    }

    private static final String getOrCreateAppStorageDirctory(File externalStorageDirectory,
                                                              String subDir, boolean needCreateDir) {
        if (externalStorageDirectory == null) {
            return null;
        }
        String appStorageDir = externalStorageDirectory.getParent() + File.separator
                + externalStorageDirectory.getName() + File.separator;
        if (subDir != null) {
            appStorageDir += subDir;
        }
        final File appStorageFile = new File(appStorageDir);
        if (!needCreateDir) {
            return appStorageDir;
        }
        if (appStorageFile.exists() || appStorageFile.mkdirs()) {
            return appStorageDir;
        }
        return null;
    }

    public static boolean move(String src, String dest) {
        if (src == null || dest == null) {
            return false;
        }
        final File file = new File(src);
        if (file.exists()) {
            return file.renameTo(new File(dest));
        }
        return false;
    }

    public static String getInternalCacheForUri(Uri sourceUri) {
        try {
            String directory = FileUtil.getAppStorageDirectory("cache");
            String fileName = sourceUri.getLastPathSegment();
            File outputFile = new File(directory, fileName);
            outputFile.createNewFile();
            outputFile.deleteOnExit();  //Onetime cache file. No need to keep it.

            InputStream in = JkFrame.getApplication().getContentResolver().openInputStream(sourceUri);
            if (in != null) {
                OutputStream out = new FileOutputStream(outputFile);
                IoUtils.copyStream(in, out);
            }

            return outputFile.getPath();
        } catch (IOException e) {
        }
        return null;
    }
}
