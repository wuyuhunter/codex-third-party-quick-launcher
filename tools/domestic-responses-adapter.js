const http = require("http");
const { createHash, randomUUID } = require("crypto");

function readPort() {
  const portArgIndex = process.argv.indexOf("--port");
  if (portArgIndex >= 0 && process.argv[portArgIndex + 1]) {
    return Number(process.argv[portArgIndex + 1]);
  }
  return Number(process.env.DOMESTIC_RESPONSES_ADAPTER_PORT || 8787);
}

const PORT = readPort();
const ADAPTER_NAME = "codex-domestic-responses-adapter";
const ADAPTER_VERSION = "v0.5.5";
const HEALTH_TOKEN = process.env.DOMESTIC_RESPONSES_ADAPTER_HEALTH_TOKEN || "";

const providers = {
  qwen: {
    baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    wireApi: "responses",
  },
  deepseek: {
    baseUrl: "https://api.deepseek.com",
    wireApi: "chat",
  },
  kimi: {
    baseUrl: "https://api.moonshot.cn/v1",
    wireApi: "chat",
  },
  glm: {
    baseUrl: "https://open.bigmodel.cn/api/paas/v4",
    wireApi: "chat",
  },
  minimax: {
    baseUrl: "https://api.minimax.chat/v1",
    wireApi: "chat",
  },
  tencent: {
    baseUrl: "https://tokenhub.tencentmaas.com/v1",
    wireApi: "chat",
  },
  mimo: {
    baseUrl: "https://api.xiaomimimo.com/v1",
    wireApi: "chat",
    authHeader: "api-key",
  },
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.setEncoding("utf8");
    req.on("data", chunk => { data += chunk; });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

function normalizeRole(role) {
  const value = String(role || "user").toLowerCase();
  if (value === "developer" || value === "latest_reminder") {
    return "system";
  }
  if (value === "system" || value === "user" || value === "assistant" || value === "tool") {
    return value;
  }
  return "user";
}

function normalizeUpstreamModel(provider, model) {
  const value = String(model || "");
  if (provider === "minimax" && value.toLowerCase() === "minimax2.7") {
    return "MiniMax-M2.7";
  }
  return value;
}

function flattenContent(content) {
  if (typeof content === "string") {
    return content;
  }
  if (Array.isArray(content)) {
    return content.map(part => {
      if (typeof part === "string") return part;
      return part.text || part.input_text || part.output_text || "";
    }).join("\n");
  }
  return String(content ?? "");
}

function normalizeToolArguments(args) {
  if (typeof args === "string") {
    return args;
  }
  return JSON.stringify(args ?? {});
}

function appendInputItem(messages, item) {
  if (typeof item === "string") {
    messages.push({ role: "user", content: item });
    return;
  }

  if (item && item.type === "function_call") {
    messages.push({
      role: "assistant",
      content: "",
      tool_calls: [{
        id: item.call_id || item.id || `call_${randomUUID().replace(/-/g, "")}`,
        type: "function",
        function: {
          name: item.name || "",
          arguments: normalizeToolArguments(item.arguments),
        },
      }],
    });
    return;
  }

  if (item && item.type === "function_call_output") {
    messages.push({
      role: "tool",
      tool_call_id: item.call_id || item.id || "",
      content: flattenContent(item.output ?? item.content ?? ""),
    });
    return;
  }

  if (item && item.type === "message") {
    messages.push({
      role: normalizeRole(item.role || "user"),
      content: flattenContent(item.content),
    });
    return;
  }

  if (item && item.role && item.content !== undefined) {
    messages.push({
      role: normalizeRole(item.role),
      content: flattenContent(item.content),
    });
    return;
  }

  messages.push({ role: "user", content: JSON.stringify(item ?? "") });
}

function appendFunctionCallGroup(messages, items) {
  const toolCalls = items.map(item => ({
    id: item.call_id || item.id || `call_${randomUUID().replace(/-/g, "")}`,
    type: "function",
    function: {
      name: item.name || "",
      arguments: normalizeToolArguments(item.arguments),
    },
  }));
  messages.push({
    role: "assistant",
    content: "",
    tool_calls: toolCalls,
  });
}

function normalizeChatMessages(provider, request) {
  const messages = [];
  if (request.instructions) {
    messages.push({
      role: "system",
      content: flattenContent(request.instructions),
    });
  }
  if (Array.isArray(request.input)) {
    for (let index = 0; index < request.input.length; index++) {
      const item = request.input[index];
      if (item && item.type === "function_call") {
        const group = [];
        while (index < request.input.length && request.input[index] && request.input[index].type === "function_call") {
          group.push(request.input[index]);
          index += 1;
        }
        index -= 1;
        appendFunctionCallGroup(messages, group);
        continue;
      }
      appendInputItem(messages, item);
    }
  } else {
    appendInputItem(messages, request.input);
  }

  if (provider !== "minimax") {
    return messages;
  }

  const systemMessages = messages.filter(message => message.role === "system");
  const otherMessages = messages.filter(message => message.role !== "system");
  if (systemMessages.length <= 1) {
    return messages;
  }
  return [{
    role: "system",
    content: systemMessages.map(message => flattenContent(message.content)).filter(Boolean).join("\n\n"),
  }, ...otherMessages];
}

function normalizeChatTools(tools) {
  if (!Array.isArray(tools)) {
    return [];
  }
  return tools
    .filter(tool => tool && tool.type === "function" && tool.name)
    .map(tool => {
      const fn = {
        name: tool.name,
        description: tool.description || "",
        parameters: tool.parameters || { type: "object", properties: {} },
      };
      if (typeof tool.strict === "boolean") {
        fn.strict = tool.strict;
      }
      return { type: "function", function: fn };
    });
}

function normalizeChatToolChoice(choice) {
  if (!choice || choice === "auto" || choice === "none" || choice === "required") {
    return choice;
  }
  if (typeof choice === "object" && choice.type === "function") {
    const name = choice.name || (choice.function && choice.function.name);
    if (name) {
      return { type: "function", function: { name } };
    }
  }
  return undefined;
}

function cleanChatText(provider, text) {
  const value = String(text || "");
  if (provider !== "minimax") {
    return value;
  }
  const cleaned = value.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
  return cleaned || value;
}

async function callResponses(provider, auth, request, upstreamModel) {
  const upstream = providers[provider];
  if (!upstream || upstream.wireApi !== "responses") {
    const err = new Error(`Unknown responses provider: ${provider}`);
    err.statusCode = 404;
    throw err;
  }

  const body = { ...request, model: normalizeUpstreamModel(provider, upstreamModel || request.model) };
  const response = await fetch(`${upstream.baseUrl}/responses`, {
    method: "POST",
    headers: {
      "authorization": auth,
      "content-type": "application/json",
      "accept": request.stream ? "text/event-stream" : "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    const err = new Error(text || response.statusText);
    err.statusCode = response.status;
    throw err;
  }
  return {
    contentType: response.headers.get("content-type") || "",
    text,
  };
}

async function callChat(provider, auth, request, upstreamModel) {
  const upstream = providers[provider];
  if (!upstream) {
    const err = new Error(`Unknown provider: ${provider}`);
    err.statusCode = 404;
    throw err;
  }

  const effectiveModel = normalizeUpstreamModel(provider, upstreamModel || request.model);
  let temperature = request.temperature;
  const isKimiK2 = provider === "kimi" && String(effectiveModel || "").startsWith("kimi-k2.");
  if (temperature === undefined || temperature === null) {
    temperature = isKimiK2 ? 0.6 : (provider === "minimax" ? 0.2 : 0);
  }
  if (isKimiK2) {
    temperature = 0.6;
  }

  const body = {
    model: effectiveModel,
    messages: normalizeChatMessages(provider, request),
    temperature,
  };
  if (request.max_output_tokens) {
    body.max_tokens = request.max_output_tokens;
  }
  const tools = normalizeChatTools(request.tools);
  if (tools.length) {
    body.tools = tools;
    const toolChoice = normalizeChatToolChoice(request.tool_choice);
    if (toolChoice) {
      body.tool_choice = toolChoice;
    }
    if (typeof request.parallel_tool_calls === "boolean") {
      body.parallel_tool_calls = request.parallel_tool_calls;
    }
  }

  if (provider === "glm" && String(effectiveModel || "").startsWith("glm-5.1")) {
    body.thinking = { type: "disabled" };
  }
  if (provider === "deepseek" && tools.length) {
    body.thinking = { type: "disabled" };
  }
  if (isKimiK2) {
    body.thinking = { type: "disabled" };
  }

  const upstreamAuth = upstream.authHeader === "api-key"
    ? String(auth || "").replace(/^Bearer\s+/i, "")
    : auth;
  const response = await fetch(`${upstream.baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      [upstream.authHeader || "authorization"]: upstreamAuth,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    const err = new Error(text || response.statusText);
    err.statusCode = response.status;
    throw err;
  }
  const json = JSON.parse(text);
  const choice = json.choices && json.choices[0];
  const message = choice && choice.message ? choice.message : {};
  if (Array.isArray(message.tool_calls) && message.tool_calls.length) {
    return {
      type: "tool_calls",
      toolCalls: message.tool_calls.map(call => ({
        id: call.id || `call_${randomUUID().replace(/-/g, "")}`,
        name: call.function && call.function.name ? call.function.name : call.name || "",
        arguments: call.function && call.function.arguments !== undefined
          ? normalizeToolArguments(call.function.arguments)
          : normalizeToolArguments(call.arguments),
      })),
    };
  }
  return {
    type: "text",
    text: cleanChatText(provider, message.content || message.reasoning_content || ""),
  };
}

function responsePayload(model, result) {
  const responseId = `resp_${randomUUID().replace(/-/g, "")}`;
  const value = typeof result === "string" ? { type: "text", text: result } : (result || { type: "text", text: "" });
  const output = value.type === "tool_calls"
    ? value.toolCalls.map(call => ({
      id: `fc_${randomUUID().replace(/-/g, "")}`,
      type: "function_call",
      status: "completed",
      call_id: call.id,
      name: call.name,
      arguments: normalizeToolArguments(call.arguments),
    }))
    : [{
      id: `msg_${randomUUID().replace(/-/g, "")}`,
      type: "message",
      status: "completed",
      role: "assistant",
      content: [{
        type: "output_text",
        text: value.text || "",
        annotations: [],
      }],
    }];
  return {
    id: responseId,
    object: "response",
    created_at: Math.floor(Date.now() / 1000),
    status: "completed",
    model,
    output,
    output_text: value.type === "tool_calls" ? "" : (value.text || ""),
    usage: {
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
    },
  };
}

function signHealth(nonce) {
  if (!HEALTH_TOKEN) {
    return "";
  }
  return createHash("sha256")
    .update(`${HEALTH_TOKEN}:${ADAPTER_NAME}:${ADAPTER_VERSION}:${PORT}:${nonce || ""}`)
    .digest("hex");
}

function writeSse(res, payload) {
  const text = payload.output_text || "";
  let sequence = 0;
  res.writeHead(200, {
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-cache",
    "connection": "keep-alive",
  });
  const send = (event, data) => {
    res.write(`event:${event}\n`);
    res.write(`data:${JSON.stringify({ sequence_number: sequence++, type: event, ...data })}\n\n`);
  };
  send("response.created", { response: { ...payload, status: "queued", output: [] } });
  send("response.in_progress", { response: { ...payload, status: "in_progress", output: [] } });
  payload.output.forEach((item, outputIndex) => {
    send("response.output_item.added", {
      output_index: outputIndex,
      item: item.type === "message" ? { ...item, status: "in_progress", content: [] } : { ...item, status: "in_progress" },
    });
    if (item.type === "function_call") {
      send("response.function_call_arguments.delta", {
        output_index: outputIndex,
        item_id: item.id,
        delta: item.arguments || "",
      });
      send("response.function_call_arguments.done", {
        output_index: outputIndex,
        item_id: item.id,
        arguments: item.arguments || "",
      });
    } else {
      const itemText = item.content && item.content[0] ? item.content[0].text || "" : text;
      send("response.content_part.added", {
        output_index: outputIndex,
        content_index: 0,
        item_id: item.id,
        part: { type: "output_text", annotations: [], text: "" },
      });
      send("response.output_text.delta", {
        output_index: outputIndex,
        content_index: 0,
        item_id: item.id,
        delta: itemText,
        logprobs: [],
      });
      send("response.output_text.done", {
        output_index: outputIndex,
        content_index: 0,
        item_id: item.id,
        text: itemText,
        logprobs: [],
      });
      send("response.content_part.done", {
        output_index: outputIndex,
        content_index: 0,
        item_id: item.id,
        part: { type: "output_text", annotations: [], text: itemText },
      });
    }
    send("response.output_item.done", { output_index: outputIndex, item });
  });
  send("response.completed", { response: payload });
  res.write("data: [DONE]\n\n");
  res.end();
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://127.0.0.1");
    const match = url.pathname.match(/^\/([^/]+)(?:\/([^/]+))?\/v1\/responses$/);
    if (req.method === "GET" && url.pathname === "/health") {
      const nonce = url.searchParams.get("nonce") || "";
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({
        ok: true,
        name: ADAPTER_NAME,
        version: ADAPTER_VERSION,
        pid: process.pid,
        port: PORT,
        nonce,
        signature: signHealth(nonce),
      }));
      return;
    }
    if (req.method !== "POST" || !match) {
      res.writeHead(404, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: "not_found" }));
      return;
    }
    const provider = match[1];
    const upstreamModel = match[2] ? decodeURIComponent(match[2]) : "";
    const auth = req.headers.authorization || "";
    const request = JSON.parse(await readBody(req) || "{}");
    if (providers[provider] && providers[provider].wireApi === "responses") {
      const upstreamResponse = await callResponses(provider, auth, request, upstreamModel);
      res.writeHead(200, { "content-type": upstreamResponse.contentType || (request.stream ? "text/event-stream; charset=utf-8" : "application/json") });
      res.end(upstreamResponse.text);
      return;
    }
    const result = await callChat(provider, auth, request, upstreamModel);
    const payload = responsePayload(upstreamModel || request.model, result);
    if (request.stream) {
      writeSse(res, payload);
    } else {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(payload));
    }
  } catch (err) {
    const status = err.statusCode || 500;
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: { message: err.message || String(err) } }));
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`${ADAPTER_NAME} ${ADAPTER_VERSION} listening on http://127.0.0.1:${PORT}`);
});

