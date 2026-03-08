package com.github.Bahaaio.userservice.repository;

import com.github.Bahaaio.userservice.model.User;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<User, Long> {
}
