package com.github.Bahaaio.monolith.repository;

import com.github.Bahaaio.monolith.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface UserRepository extends JpaRepository<User, Long> {
}
