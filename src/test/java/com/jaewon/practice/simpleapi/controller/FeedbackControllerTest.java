package com.jaewon.practice.simpleapi.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jaewon.practice.simpleapi.dto.FeedbackRequest;
import com.jaewon.practice.simpleapi.dto.FeedbackResponse;
import com.jaewon.practice.simpleapi.dto.PageResponse;
import com.jaewon.practice.simpleapi.service.FeedbackService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(FeedbackController.class)
@DisplayName("FeedbackController API 테스트")
class FeedbackControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private FeedbackService feedbackService;

    @Test
    @DisplayName("POST /api/feedbacks - 피드백 생성 성공")
    void createFeedback_Success() throws Exception {
        // given
        FeedbackRequest request = new FeedbackRequest("테스트유저", "테스트 메시지입니다");
        FeedbackResponse response = new FeedbackResponse(
                1L,
                "테스트유저",
                "테스트 메시지입니다",
                LocalDateTime.now()
        );

        when(feedbackService.createFeedback(any(FeedbackRequest.class)))
                .thenReturn(response);

        // when & then
        mockMvc.perform(post("/api/feedbacks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.message").value("피드백이 등록되었습니다"))
                .andExpect(jsonPath("$.data.id").value(1))
                .andExpect(jsonPath("$.data.username").value("테스트유저"))
                .andExpect(jsonPath("$.data.message").value("테스트 메시지입니다"));
    }

    @Test
    @DisplayName("POST /api/feedbacks - 메시지가 비어있으면 400 에러")
    void createFeedback_EmptyMessage_BadRequest() throws Exception {
        // given
        FeedbackRequest request = new FeedbackRequest("테스트유저", "");

        // when & then
        mockMvc.perform(post("/api/feedbacks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.error").value("Validation Failed"))
                .andExpect(jsonPath("$.message").value("입력값 검증에 실패했습니다"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("message"))
                .andExpect(jsonPath("$.fieldErrors[0].message").value("메시지는 필수입니다"));
    }

    @Test
    @DisplayName("POST /api/feedbacks - 메시지가 null이면 400 에러")
    void createFeedback_NullMessage_BadRequest() throws Exception {
        // given
        FeedbackRequest request = new FeedbackRequest("테스트유저", null);

        // when & then
        mockMvc.perform(post("/api/feedbacks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.message").value("입력값 검증에 실패했습니다"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("message"));
    }

    @Test
    @DisplayName("POST /api/feedbacks - 메시지가 1000자를 초과하면 400 에러")
    void createFeedback_MessageTooLong_BadRequest() throws Exception {
        // given
        String longMessage = "a".repeat(1001);
        FeedbackRequest request = new FeedbackRequest("테스트유저", longMessage);

        // when & then
        mockMvc.perform(post("/api/feedbacks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.message").value("입력값 검증에 실패했습니다"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("message"));
    }

    @Test
    @DisplayName("POST /api/feedbacks - 사용자 이름이 100자를 초과하면 400 에러")
    void createFeedback_UsernameTooLong_BadRequest() throws Exception {
        // given
        String longUsername = "a".repeat(101);
        FeedbackRequest request = new FeedbackRequest(longUsername, "테스트 메시지");

        // when & then
        mockMvc.perform(post("/api/feedbacks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.message").value("입력값 검증에 실패했습니다"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("username"));
    }

    @Test
    @DisplayName("POST /api/feedbacks - 익명 피드백 생성 성공 (username null)")
    void createFeedback_AnonymousUser_Success() throws Exception {
        // given
        FeedbackRequest request = new FeedbackRequest(null, "익명 메시지입니다");
        FeedbackResponse response = new FeedbackResponse(
                1L,
                "익명",
                "익명 메시지입니다",
                LocalDateTime.now()
        );

        when(feedbackService.createFeedback(any(FeedbackRequest.class)))
                .thenReturn(response);

        // when & then
        mockMvc.perform(post("/api/feedbacks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.username").value("익명"));
    }

    @Test
    @DisplayName("GET /api/feedbacks - 전체 피드백 조회 성공 (페이징)")
    void getAllFeedbacks_Success() throws Exception {
        // given
        List<FeedbackResponse> feedbackList = List.of(
                new FeedbackResponse(1L, "유저1", "메시지1", LocalDateTime.now()),
                new FeedbackResponse(2L, "유저2", "메시지2", LocalDateTime.now())
        );
        Page<FeedbackResponse> page = new PageImpl<>(feedbackList, PageRequest.of(0, 20), 2);
        PageResponse<FeedbackResponse> pageResponse = PageResponse.of(page);

        when(feedbackService.getAllFeedbacks(any(Pageable.class)))
                .thenReturn(pageResponse);

        // when & then
        mockMvc.perform(get("/api/feedbacks")
                        .param("page", "0")
                        .param("size", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.content").isArray())
                .andExpect(jsonPath("$.data.content.length()").value(2))
                .andExpect(jsonPath("$.data.currentPage").value(0))
                .andExpect(jsonPath("$.data.size").value(20))
                .andExpect(jsonPath("$.data.totalElements").value(2))
                .andExpect(jsonPath("$.data.totalPages").value(1));
    }

    @Test
    @DisplayName("GET /api/feedbacks - 기본 페이지 파라미터 (page=0, size=20)")
    void getAllFeedbacks_DefaultPageParameters() throws Exception {
        // given
        Page<FeedbackResponse> page = new PageImpl<>(List.of(), PageRequest.of(0, 20), 0);
        PageResponse<FeedbackResponse> pageResponse = PageResponse.of(page);

        when(feedbackService.getAllFeedbacks(PageRequest.of(0, 20)))
                .thenReturn(pageResponse);

        // when & then
        mockMvc.perform(get("/api/feedbacks"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.currentPage").value(0))
                .andExpect(jsonPath("$.data.size").value(20));
    }

    @Test
    @DisplayName("GET /api/feedbacks?username=테스트 - 사용자별 피드백 조회 성공")
    void getFeedbacksByUsername_Success() throws Exception {
        // given
        String username = "테스트유저";
        List<FeedbackResponse> feedbackList = List.of(
                new FeedbackResponse(1L, username, "메시지1", LocalDateTime.now()),
                new FeedbackResponse(2L, username, "메시지2", LocalDateTime.now())
        );
        Page<FeedbackResponse> page = new PageImpl<>(feedbackList, PageRequest.of(0, 20), 2);
        PageResponse<FeedbackResponse> pageResponse = PageResponse.of(page);

        when(feedbackService.getFeedbacksByUsername(eq(username), any(Pageable.class)))
                .thenReturn(pageResponse);

        // when & then
        mockMvc.perform(get("/api/feedbacks")
                        .param("username", username)
                        .param("page", "0")
                        .param("size", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.content").isArray())
                .andExpect(jsonPath("$.data.content.length()").value(2))
                .andExpect(jsonPath("$.data.content[0].username").value(username))
                .andExpect(jsonPath("$.data.content[1].username").value(username));
    }

    @Test
    @DisplayName("GET /api/feedbacks?username= - 빈 username은 전체 조회로 처리")
    void getFeedbacksByUsername_EmptyUsername_ReturnsAll() throws Exception {
        // given
        Page<FeedbackResponse> page = new PageImpl<>(List.of(), PageRequest.of(0, 20), 0);
        PageResponse<FeedbackResponse> pageResponse = PageResponse.of(page);

        when(feedbackService.getAllFeedbacks(any(Pageable.class)))
                .thenReturn(pageResponse);

        // when & then
        mockMvc.perform(get("/api/feedbacks")
                        .param("username", "")
                        .param("page", "0")
                        .param("size", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));
    }

    @Test
    @DisplayName("GET /api/feedbacks - 빈 결과 조회 성공")
    void getAllFeedbacks_EmptyResult() throws Exception {
        // given
        Page<FeedbackResponse> page = new PageImpl<>(List.of(), PageRequest.of(0, 20), 0);
        PageResponse<FeedbackResponse> pageResponse = PageResponse.of(page);

        when(feedbackService.getAllFeedbacks(any(Pageable.class)))
                .thenReturn(pageResponse);

        // when & then
        mockMvc.perform(get("/api/feedbacks"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.content").isArray())
                .andExpect(jsonPath("$.data.content.length()").value(0))
                .andExpect(jsonPath("$.data.totalElements").value(0));
    }
}
