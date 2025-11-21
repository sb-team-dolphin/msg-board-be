package com.jaewon.practice.simpleapi.dto;

import com.jaewon.practice.simpleapi.entity.Feedback;
import lombok.AllArgsConstructor;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@AllArgsConstructor
public class FeedbackResponse {

    private Long id;
    private String username;
    private String message;
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
