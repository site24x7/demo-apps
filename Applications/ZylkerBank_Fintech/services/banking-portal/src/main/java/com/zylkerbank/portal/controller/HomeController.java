package com.zylkerbank.portal.controller;

import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class HomeController {

    @GetMapping("/")
    public String home(HttpSession session, Model model) {
        if (session != null && session.getAttribute("user") != null) {
            model.addAttribute("user", session.getAttribute("user"));
        }
        return "index";
    }
}
