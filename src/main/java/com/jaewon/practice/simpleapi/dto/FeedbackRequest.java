package com.jaewon.practice.simpleapi.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
@AllArgsConstructor
public class FeedbackRequest {

    @Size(max = 100, message = "사용자 이름은 100자를 초과할 수 없습니다")
    private String username;

    @NotBlank(message = "메시지는 필수입니다")
    @Size(max = 1000, message = "메시지는 1000자를 초과할 수 없습니다")
    private String message;
}
