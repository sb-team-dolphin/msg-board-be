package com.jaewon.practice.simpleapi.controller;

import com.jaewon.practice.simpleapi.dto.ApiResponse;
import com.jaewon.practice.simpleapi.dto.FeedbackRequest;
import com.jaewon.practice.simpleapi.dto.FeedbackResponse;
import com.jaewon.practice.simpleapi.dto.PageResponse;
import com.jaewon.practice.simpleapi.service.FeedbackService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/feedbacks")
@RequiredArgsConstructor
public class FeedbackController {

    private final FeedbackService feedbackService;

    /**
     * 피드백 메시지 등록
     * POST /api/feedbacks
     */
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
    @GetMapping
    public ResponseEntity<ApiResponse<PageResponse<FeedbackResponse>>> getAllFeedbacks(
            @RequestParam(required = false) String username,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {

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
