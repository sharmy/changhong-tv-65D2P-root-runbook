package org.sharmy.chsource;

import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;

/**
 * 极简 adb 协议客户端 —— 只做一件事：连上本机的 adbd，执行一条 shell 命令，取回输出。
 *
 * 为什么需要它：电视要把 keylayout bind mount 上去（修遥控器主页键）必须 root，
 * 而本机 /system/xbin/su 是 root:shell、/system/xbin/csu 有 uid 白名单，
 * 第三方 app 都提不了权。但 adbd 是以 root 运行的，且 ro.adb.secure=0
 * （不校验 RSA 密钥），所以 app 走 127.0.0.1:5555 就能拿到 root shell，
 * 全程在电视内部完成，不需要电脑。
 *
 * 协议（AOSP system/core/adb/protocol.txt 的最小子集）：
 *   24 字节头: command / arg0 / arg1 / data_length / data_check / magic(=command^0xffffffff)
 *   流程: 发 CNXN(host::) → 收 CNXN → 发 OPEN(shell:cmd) → 收 OKAY → 收 WRTE/CLSE
 */
public final class MiniAdb {

    private static final int CNXN = 0x4e584e43;
    private static final int OPEN = 0x4e45504f;
    private static final int OKAY = 0x59414b4f;
    private static final int CLSE = 0x45534c43;
    private static final int WRTE = 0x45545257;

    private MiniAdb() {
    }

    public static String shell(String host, int port, String cmd, int timeoutMs) {
        Socket s = null;
        DataOutputStream out = null;
        DataInputStream in = null;
        try {
            s = new Socket();
            s.connect(new InetSocketAddress(host, port), timeoutMs);
            s.setSoTimeout(timeoutMs);
            out = new DataOutputStream(s.getOutputStream());
            in = new DataInputStream(s.getInputStream());

            send(out, CNXN, 0x01000000, 4096, "host::\0");
            read(in);                                   // 服务端的 CNXN
            send(out, OPEN, 1, 0, "shell:" + cmd + "\0");

            ByteArrayOutputStream result = new ByteArrayOutputStream();
            while (true) {
                Msg m = read(in);
                if (m == null) {
                    break;
                }
                if (m.cmd == WRTE) {
                    result.write(m.data, 0, m.data.length);
                    send(out, OKAY, m.arg1, m.arg0, null);   // ack，让对端继续发
                } else if (m.cmd == CLSE) {
                    break;
                }
            }
            return new String(result.toByteArray(), "UTF-8");
        } catch (Throwable t) {
            return "ERR: " + t;
        } finally {
            // ⚠ 三个都得关。app 的 fd 上限只有 1024，本方法每 60~120 秒被调用一次，
            //   漏一个就是几小时内把 fd 耗尽 —— 之后连 Runtime.exec 都会报
            //   "Too many open files"，自愈彻底失效（踩过）。
            if (out != null) {
                try { out.close(); } catch (Throwable ignore) { }
            }
            if (in != null) {
                try { in.close(); } catch (Throwable ignore) { }
            }
            if (s != null) {
                try { s.close(); } catch (Throwable ignore) { }
            }
        }
    }

    private static final class Msg {
        int cmd;
        int arg0;
        int arg1;
        byte[] data;
    }

    private static Msg read(DataInputStream in) throws java.io.IOException {
        Msg m = new Msg();
        m.cmd = Integer.reverseBytes(in.readInt());
        m.arg0 = Integer.reverseBytes(in.readInt());
        m.arg1 = Integer.reverseBytes(in.readInt());
        int len = Integer.reverseBytes(in.readInt());
        Integer.reverseBytes(in.readInt());      // data_check，不校验
        Integer.reverseBytes(in.readInt());      // magic，不校验
        m.data = new byte[0];
        if (len > 0 && len < 1024 * 1024) {
            m.data = new byte[len];
            in.readFully(m.data);
        }
        return m;
    }

    private static void send(DataOutputStream o, int cmd, int a0, int a1, String data)
            throws java.io.IOException {
        byte[] d = (data == null) ? new byte[0] : data.getBytes("UTF-8");
        o.writeInt(Integer.reverseBytes(cmd));
        o.writeInt(Integer.reverseBytes(a0));
        o.writeInt(Integer.reverseBytes(a1));
        o.writeInt(Integer.reverseBytes(d.length));
        o.writeInt(Integer.reverseBytes(sum(d)));
        o.writeInt(Integer.reverseBytes(cmd ^ 0xffffffff));
        if (d.length > 0) {
            o.write(d);
        }
        o.flush();
    }

    private static int sum(byte[] d) {
        int s = 0;
        for (byte b : d) {
            s += (b & 0xff);
        }
        return s;
    }
}
