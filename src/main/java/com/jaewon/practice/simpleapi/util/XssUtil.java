package com.jaewon.practice.simpleapi.util;

import org.apache.commons.text.StringEscapeUtils;

public class XssUtil {

    public static String escape(String value) {
        if (value == null) {
            return null;
        }
        return StringEscapeUtils.escapeHtml4(value);
    }

    public static String clean(String value) {
        if (value == null) {
            return null;
        }

        // 위험한 HTML 태그 제거
        value = value.replaceAll("<script>", "");
        value = value.replaceAll("</script>", "");
        value = value.replaceAll("<iframe>", "");
        value = value.replaceAll("</iframe>", "");
        value = value.replaceAll("javascript:", "");
        value = value.replaceAll("onerror=", "");
        value = value.replaceAll("onload=", "");

        return StringEscapeUtils.escapeHtml4(value);
    }
}
