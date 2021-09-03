package com.osmapps.framework;

import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.InputStreamReader;

import com.google.common.base.Strings;
import com.osmapps.framework.util.IoUtils;

import android.app.Application;
import android.content.Context;

/**
 * @author wlei 2014-5-13
 */
public class JkFrame {

  private static boolean isDebug = false;
  private static Application application;
  private static String processName;

  private JkFrame() {
  }

  public static boolean isDebug() {
    return isDebug;
  }

  public static Application getApplication() {
    return application;
  }

  public static void init(Application application) {
    JkFrame.application = application;
  }

  public static void setIsDebug(boolean isDebug) {
    JkFrame.isDebug = isDebug;
  }

  public static boolean isMainProcess() {
    String mainProcessName = application.getPackageName();
    if (Strings.isNullOrEmpty(processName)) {
      processName = getProcessName();
    }
    return processName.equals(mainProcessName);
  }

  public static String getProcessName() {
    BufferedReader cmdlineReader = null;
    try {
      cmdlineReader = new BufferedReader(new InputStreamReader(
          new FileInputStream("/proc" + android.os.Process.myPid() + "/cmdline"), "iso-8859-1"));
      int c;
      StringBuilder processName = new StringBuilder();
      while ((c = cmdlineReader.read()) > 0) {
        processName.append((char) c);
      }
      return processName.toString();
    } catch (Exception e) {
      android.app.ActivityManager am =
          (android.app.ActivityManager) application.getSystemService(Context.ACTIVITY_SERVICE);
      if (am != null) {
        int myPid = android.os.Process.myPid();
        for (android.app.ActivityManager.RunningAppProcessInfo processInfo : am
            .getRunningAppProcesses()) {
          if (processInfo.pid == myPid) {
            return processInfo.processName;
          }
        }
      }
      return "";
    } finally {
      if (cmdlineReader != null) {
        IoUtils.closeSilently(cmdlineReader);
      }
    }
  }
}
