#!/usr/bin/env bash
set -u

turn_number=0
waiting_for_tool_response=0
descendant_started=0
while IFS= read -r line; do
  case "$line" in
    *'"method":"initialize"'*)
      if [[ "$descendant_started" -eq 0 ]]; then
        sleep 300 &
        printf '%s\n' "$!" > .fake-descendant.pid
        descendant_started=1
      fi
      printf '%s\n' '{"id":1,"result":{"serverInfo":{"name":"fake-codex","version":"test"}}}'
      ;;
    *'"method":"thread/start"'*)
      printf '%s\n' '{"id":2,"result":{"thread":{"id":"thread-mock"}}}'
      ;;
    *'"method":"turn/start"'*)
      turn_number=$((turn_number + 1))
      printf '{"id":3,"result":{"turn":{"id":"turn-%s"}}}\n' "$turn_number"
      if [[ "$turn_number" -eq 1 ]]; then
        printf '%s\n' '{"payload":{"token":"SYMPHONY_PROTOCOL_SECRET_SENTINEL"}}'
      fi
      printf '{"method":"thread/tokenUsage/updated","params":{"threadId":"thread-mock","turnId":"turn-%s","tokenUsage":{"last":{"cachedInputTokens":0,"inputTokens":1,"outputTokens":2,"reasoningOutputTokens":0,"totalTokens":3},"total":{"cachedInputTokens":0,"inputTokens":%s,"outputTokens":2,"reasoningOutputTokens":0,"totalTokens":%s}}}}\n' "$turn_number" "$turn_number" "$((turn_number + 2))"
      if [[ "$turn_number" -eq 1 ]]; then
        printf '%s\n' '{"method":"account/rateLimits/updated","params":{"rateLimits":{"planType":"plus","primary":{"usedPercent":7}}}}'
      fi
      if [[ "$turn_number" -eq 1 ]]; then
        waiting_for_tool_response=1
        printf '%s\n' '{"id":"tool-1","method":"item/tool/call","params":{"tool":"not-implemented","arguments":{}}}'
      else
        printf '{"method":"turn/completed","params":{"turn":{"id":"turn-%s","status":"completed"}}}\n' "$turn_number"
        exit 0
      fi
      ;;
    *)
      if [[ "$waiting_for_tool_response" -eq 1 ]]; then
        if [[ "$line" == *'"id":"tool-1"'* && "$line" == *'"success":false'* && "$line" == *'"contentItems"'* && "$line" == *'"type":"inputText"'* ]]; then
          waiting_for_tool_response=0
          printf '%s\n' '{"method":"turn/completed","params":{"turn":{"id":"turn-1","status":"completed"}}}'
        else
          printf '%s\n' 'invalid unsupported-tool response' >&2
          exit 9
        fi
      fi
      ;;
  esac
done
