package com.jaewon.practice.simpleapi.dto;

import com.jaewon.practice.simpleapi.entity.Feedback;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Getter;

import java.time.LocalDateTime;

@Schema(description = "피드백 응답")
@Getter
@AllArgsConstructor
public class FeedbackResponse {

    @Schema(description = "피드백 ID", example = "1")
    private Long id;

    @Schema(description = "사용자 이름", example = "홍길동")
    private String username;

    @Schema(description = "피드백 메시지", example = "서비스가 매우 좋습니다!")
    private String message;

    @Schema(description = "생성 일시", example = "2025-11-22T10:30:00")
    private LocalDateTime createdAt;

    public static FeedbackResponse from(Feedback feedback) {
        return new FeedbackResponse(
                feedback.getId(),
                feedback.getUsername() != null ? feedback.getUsername() : "익명",
                feedback.getMessage(),
                feedback.getCreatedAt()
        );
    }
}
