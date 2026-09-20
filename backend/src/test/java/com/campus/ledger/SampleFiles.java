package com.campus.ledger;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * 读取项目根目录 samples/ 下的样例账单文件。
 * 兼容从 backend 目录或项目根目录运行测试的两种情况。
 */
public class SampleFiles {

    private static final String[] BASES = {"../samples", "samples", "../../samples"};

    private SampleFiles() {
    }

    public static Path path(String name) {
        for (String base : BASES) {
            Path candidate = Paths.get(base, name);
            if (Files.exists(candidate)) {
                return candidate;
            }
        }
        throw new IllegalStateException("找不到样例账单文件：" + name + "（请确认 samples 目录存在）");
    }

    public static byte[] bytes(String name) {
        try {
            return Files.readAllBytes(path(name));
        } catch (IOException e) {
            throw new IllegalStateException("样例账单文件读取失败：" + name, e);
        }
    }
}
