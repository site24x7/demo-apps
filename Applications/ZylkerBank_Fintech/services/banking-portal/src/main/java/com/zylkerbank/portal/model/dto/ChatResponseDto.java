package com.zylkerbank.portal.model.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;
import java.util.Map;

@JsonIgnoreProperties(ignoreUnknown = true)
public class ChatResponseDto {

    @JsonProperty("conversation_id")
    private String conversationId;

    @JsonProperty("reply")
    private String reply;

    @JsonProperty("tool_calls")
    private List<Map<String, Object>> toolCalls;

    @JsonProperty("model")
    private String model;

    @JsonProperty("usage")
    private Map<String, Object> usage;

    public ChatResponseDto() {
    }

    public String getConversationId() {
        return conversationId;
    }

    public void setConversationId(String conversationId) {
        this.conversationId = conversationId;
    }

    public String getReply() {
        return reply;
    }

    public void setReply(String reply) {
        this.reply = reply;
    }

    public List<Map<String, Object>> getToolCalls() {
        return toolCalls;
    }

    public void setToolCalls(List<Map<String, Object>> toolCalls) {
        this.toolCalls = toolCalls;
    }

    public String getModel() {
        return model;
    }

    public void setModel(String model) {
        this.model = model;
    }

    public Map<String, Object> getUsage() {
        return usage;
    }

    public void setUsage(Map<String, Object> usage) {
        this.usage = usage;
    }
}
