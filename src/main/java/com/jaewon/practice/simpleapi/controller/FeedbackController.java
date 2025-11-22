package com.jaewon.practice.simpleapi.controller;

import com.jaewon.practice.simpleapi.dto.ApiResponse;
import com.jaewon.practice.simpleapi.dto.FeedbackRequest;
import com.jaewon.practice.simpleapi.dto.FeedbackResponse;
import com.jaewon.practice.simpleapi.dto.PageResponse;
import com.jaewon.practice.simpleapi.service.FeedbackService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@Tag(name = "Feedback", description = "사용자 피드백 관리 API")
@RestController
@RequestMapping("/api/feedbacks")
@RequiredArgsConstructor
public class FeedbackController {

    private final FeedbackService feedbackService;

    /**
     * 피드백 메시지 등록
     * POST /api/feedbacks
     */
    @Operation(summary = "피드백 등록", description = "새로운 사용자 피드백을 등록합니다")
    @PostMapping
    public ResponseEntity<ApiResponse<FeedbackResponse>> createFeedback(
            @Valid @RequestBody FeedbackRequest request) {

        FeedbackResponse response = feedbackService.createFeedback(request);
        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(ApiResponse.success("피드백이 등록되었습니다", response));
    }

    /**
     * 피드백 메시지 조회 (페이지네이션)
     * GET /api/feedbacks?page=0&size=20&username=재원
     */
    @Operation(summary = "피드백 조회", description = "등록된 피드백 목록을 조회합니다. 사용자 이름으로 필터링할 수 있으며 페이지네이션을 지원합니다")
    @GetMapping
    public ResponseEntity<ApiResponse<PageResponse<FeedbackResponse>>> getAllFeedbacks(
            @Parameter(description = "필터링할 사용자 이름 (선택사항)") @RequestParam(required = false) String username,
            @Parameter(description = "페이지 번호 (0부터 시작)") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "페이지당 항목 수") @RequestParam(defaultValue = "20") int size) {

        Pageable pageable = PageRequest.of(page, size);
        PageResponse<FeedbackResponse> responses;

        if (username != null && !username.isBlank()) {
            // 사용자 이름으로 필터링
            responses = feedbackService.getFeedbacksByUsername(username, pageable);
        } else {
            // 전체 조회
            responses = feedbackService.getAllFeedbacks(pageable);
        }

        return ResponseEntity.ok(ApiResponse.success(responses));
    }
}
