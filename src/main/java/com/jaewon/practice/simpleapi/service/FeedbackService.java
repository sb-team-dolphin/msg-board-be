package com.jaewon.practice.simpleapi.service;

import com.jaewon.practice.simpleapi.dto.FeedbackRequest;
import com.jaewon.practice.simpleapi.dto.FeedbackResponse;
import com.jaewon.practice.simpleapi.dto.PageResponse;
import com.jaewon.practice.simpleapi.entity.Feedback;
import com.jaewon.practice.simpleapi.repository.FeedbackRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class FeedbackService {

    private final FeedbackRepository feedbackRepository;

    @Transactional
    public FeedbackResponse createFeedback(FeedbackRequest request) {
        log.info("Creating feedback - username: {}, message length: {}",
                request.getUsername(), request.getMessage().length());

        Feedback feedback = new Feedback(request.getUsername(), request.getMessage());
        Feedback savedFeedback = feedbackRepository.save(feedback);

        log.info("Feedback created successfully - id: {}", savedFeedback.getId());
        return FeedbackResponse.from(savedFeedback);
    }

    public PageResponse<FeedbackResponse> getAllFeedbacks(Pageable pageable) {
        log.info("Fetching all feedbacks - page: {}, size: {}",
                pageable.getPageNumber(), pageable.getPageSize());

        Page<Feedback> feedbackPage = feedbackRepository.findAllByOrderByCreatedAtDesc(pageable);
        Page<FeedbackResponse> responsePage = feedbackPage.map(FeedbackResponse::from);

        return PageResponse.of(responsePage);
    }

    public PageResponse<FeedbackResponse> getFeedbacksByUsername(String username, Pageable pageable) {
        log.info("Fetching feedbacks by username: {} - page: {}, size: {}",
                username, pageable.getPageNumber(), pageable.getPageSize());

        Page<Feedback> feedbackPage = feedbackRepository.findByUsernameOrderByCreatedAtDesc(username, pageable);
        Page<FeedbackResponse> responsePage = feedbackPage.map(FeedbackResponse::from);

        return PageResponse.of(responsePage);
    }
}
