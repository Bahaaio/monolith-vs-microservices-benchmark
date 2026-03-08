package com.github.Bahaaio.userservice.model;

import com.github.Bahaaio.shared.model.BaseUser;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

@Entity
@Table(name = "users")
public class User extends BaseUser {

    public User() {}

    public User(String username, String email, String firstName, String lastName) {
        super(username, email, firstName, lastName);
    }
}
