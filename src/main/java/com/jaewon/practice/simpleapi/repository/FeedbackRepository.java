package com.jaewon.practice.simpleapi.repository;

import com.jaewon.practice.simpleapi.entity.Feedback;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface FeedbackRepository extends JpaRepository<Feedback, Long> {

    // 최신순 정렬 (페이지네이션)
    Page<Feedback> findAllByOrderByCreatedAtDesc(Pageable pageable);

    // 사용자 이름으로 필터링 (페이지네이션)
    Page<Feedback> findByUsernameOrderByCreatedAtDesc(String username, Pageable pageable);

    // 기존 메서드 유지 (하위 호환)
    List<Feedback> findAllByOrderByCreatedAtDesc();
    List<Feedback> findByUsernameOrderByCreatedAtDesc(String username);
}
