if .type == "assistant" then
  .message.content[]? | select(.type == "tool_use")
  | "\(now | strftime("%H:%M:%S")) → \(.name) \(.input.command // .input.file_path // .input.skill // .input.description // "" | tostring | split("\n")[0] | .[0:100])"
elif .type == "system" and .subtype == "permission_denied" then
  "\(now | strftime("%H:%M:%S")) ✗ denied \(.tool_name)"
elif .type == "result" then
  "\n■ \(if .is_error then "ERROR" else .subtype end) · \(.num_turns) turns · $\(.total_cost_usd * 100 | round / 100)\n\(.result)",
  (.permission_denials[]? | "  denied: \(.tool_name) \(.tool_input.command // .tool_input.file_path // "")")
else empty end
