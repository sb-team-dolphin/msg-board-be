package com.jaewon.practice.simpleapi.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Schema(description = "피드백 등록 요청")
@Getter
@NoArgsConstructor
@AllArgsConstructor
public class FeedbackRequest {

    @Schema(description = "사용자 이름", example = "홍길동", maxLength = 100)
    @Size(max = 100, message = "사용자 이름은 100자를 초과할 수 없습니다")
    private String username;

    @Schema(description = "피드백 메시지", example = "서비스가 매우 좋습니다!", required = true, maxLength = 1000)
    @NotBlank(message = "메시지는 필수입니다")
    @Size(max = 1000, message = "메시지는 1000자를 초과할 수 없습니다")
    private String message;
}
