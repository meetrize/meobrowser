#import <Foundation/Foundation.h>
#import "AIBridgeToolSimulator.h"

static int gFailures = 0;

static void expect(BOOL cond, const char *msg) {
    if (!cond) {
        gFailures++;
        printf("FAIL: %s\n", msg);
    } else {
        printf("ok: %s\n", msg);
    }
}

static NSDictionary *sampleRequest(void) {
    return @{
        @"tools": @[
            @{
                @"type": @"function",
                @"function": @{
                    @"name": @"get_time",
                    @"description": @"Return current time",
                    @"parameters": @{@"type": @"object", @"properties": @{}}
                }
            },
            @{
                @"type": @"function",
                @"function": @{
                    @"name": @"write_file",
                    @"parameters": @{
                        @"type": @"object",
                        @"properties": @{
                            @"path": @{@"type": @"string"},
                            @"content": @{@"type": @"string"}
                        }
                    }
                }
            }
        ],
        @"messages": @[
            @{@"role": @"system", @"content": @"You are helpful."},
            @{@"role": @"user", @"content": @"call get_time"}
        ]
    };
}

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSDictionary *req = sampleRequest();

        expect([AIBridgeToolSimulator shouldEnableForRequest:req], "enable with tools");
        expect(![AIBridgeToolSimulator shouldEnableForRequest:@{@"tools": @[], @"messages": @[]}],
               "disable empty tools");
        expect(![AIBridgeToolSimulator shouldEnableForRequest:@{
                    @"tools": req[@"tools"],
                    @"tool_choice": @"none"
                }],
               "disable tool_choice none");
        expect([AIBridgeToolSimulator requiresToolCallsForRequest:@{
                    @"tool_choice": @"required"
                }],
               "required tool_choice");
        expect([AIBridgeToolSimulator requiresToolCallsForRequest:@{
                    @"tool_choice": @{
                        @"type": @"function",
                        @"function": @{@"name": @"get_time"}
                    }
                }],
               "forced function tool_choice");

        NSString *prompt = [AIBridgeToolSimulator buildWebpagePromptFromRequest:req];
        expect(prompt.length > 100, "prompt non-empty");
        expect([prompt containsString:@"get_time"], "prompt includes tool name");
        expect([prompt containsString:@"mode"], "prompt includes schema");

        // Bare JSON tool_calls with object arguments
        {
            NSString *text = @"{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"get_time\",\"arguments\":{}}]}";
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:text forRequest:req];
            expect(r.parseError.length == 0, "bare json no error");
            expect(r.kind == AIBridgeToolSimKindToolCalls, "bare json kind tool_calls");
            expect(r.toolCalls.count == 1, "bare json one call");
            NSDictionary *fn = r.toolCalls.firstObject[@"function"];
            expect([fn[@"name"] isEqualToString:@"get_time"], "bare json name");
            expect([fn[@"arguments"] isKindOfClass:[NSString class]], "arguments is string");
        }

        // Fenced JSON
        {
            NSString *text =
                @"Sure.\n```json\n"
                "{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"write_file\",\"arguments\":{\"path\":\"a.py\",\"content\":\"x\"}}]}\n"
                @"```\n";
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:text forRequest:req];
            expect(r.parseError.length == 0, "fenced json no error");
            expect(r.kind == AIBridgeToolSimKindToolCalls, "fenced kind");
            NSString *args = r.toolCalls.firstObject[@"function"][@"arguments"];
            expect([args containsString:@"a.py"], "fenced args path");
        }

        // Message mode
        {
            NSString *text = @"{\"mode\":\"message\",\"content\":\"done\"}";
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:text forRequest:req];
            expect(r.parseError.length == 0, "message mode ok");
            expect(r.kind == AIBridgeToolSimKindMessage, "message kind");
            expect([r.content isEqualToString:@"done"], "message content");
        }

        // Illegal tool name
        {
            NSString *text = @"{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"hack\",\"arguments\":{}}]}";
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:text forRequest:req];
            expect(r.parseError.length > 0, "illegal name errors");
            expect([r.parseError containsString:@"not allowed"], "illegal name message");
        }

        // arguments as string
        {
            NSString *text =
                @"{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"write_file\",\"arguments\":\"{\\\"path\\\":\\\"b.py\\\"}\"}]}";
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:text forRequest:req];
            expect(r.parseError.length == 0, "string args ok");
            NSString *args = r.toolCalls.firstObject[@"function"][@"arguments"];
            expect([args containsString:@"b.py"], "string args preserved");
        }

        // required but got message → error
        {
            NSDictionary *req2 = @{
                @"tools": req[@"tools"],
                @"tool_choice": @"required",
                @"messages": req[@"messages"]
            };
            NSString *text = @"{\"mode\":\"message\",\"content\":\"nope\"}";
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:text forRequest:req2];
            expect(r.parseError.length > 0, "required rejects message");
        }

        // prose without JSON
        {
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:@"把 hello.py 改成中文即可。" forRequest:req];
            expect(r.parseError.length > 0, "prose fails parse");
        }

        // OpenAI-ish without mode
        {
            NSString *text =
                @"{\"tool_calls\":[{\"id\":\"call_1\",\"function\":{\"name\":\"get_time\",\"arguments\":\"{}\"}}]}";
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:text forRequest:req];
            expect(r.parseError.length == 0, "openai-ish without mode");
            expect(r.kind == AIBridgeToolSimKindToolCalls, "openai-ish kind");
        }

        // Unescaped quotes in LLM JSON must still parse (edit_file case)
        {
            NSString *broken =
                @"{\"mode\":\"tool_calls\",\"tool_calls\":[{\"name\":\"edit_file\","
                @"\"arguments\":{\"path\":\"/Volumes/SSD4T/pro/test/hello.py\","
                @"\"edits\":[{\"old_text\":\"print(\"Hello, World!\")\","
                @"\"new_text\":\"print(\"你好，世界！\")\"}]}}]}";
            NSDictionary *req2 = @{
                @"tools": @[
                    @{@"type": @"function", @"function": @{@"name": @"edit_file", @"parameters": @{}}}
                ],
                @"messages": @[
                    @{@"role": @"system", @"content": @"roots:\n- `/Volumes/SSD4T/pro/test`\n"},
                    @{@"role": @"user", @"content": @"[@hello.py](file:///Volumes/SSD4T/pro/test/hello.py) 改成中文"}
                ]
            };
            AIBridgeToolSimResult *r = [AIBridgeToolSimulator parseWebpageText:broken forRequest:req2];
            expect(r.parseError.length == 0, "unescaped quotes repaired");
            expect(r.kind == AIBridgeToolSimKindToolCalls, "repaired kind tool_calls");
            NSString *args = r.toolCalls.firstObject[@"function"][@"arguments"];
            expect([args isKindOfClass:[NSString class]], "args string");
            id argsObj = [NSJSONSerialization JSONObjectWithData:[args dataUsingEncoding:NSUTF8StringEncoding]
                                                          options:0 error:nil];
            expect([argsObj isKindOfClass:[NSDictionary class]], "args re-parseable");
            NSString *path = argsObj[@"path"];
            expect([path isEqualToString:@"test/hello.py"], "absolute path rewritten to relative");
            NSString *oldText = argsObj[@"edits"][0][@"old_text"];
            expect([oldText isEqualToString:@"print(\"Hello, World!\")"], "old_text value restored");
        }

        // History prose (e.g. music) must not be forwarded; latest task kept
        {
            NSDictionary *polluted = @{
                @"tools": @[
                    @{@"type": @"function", @"function": @{@"name": @"edit_file", @"parameters": @{}}}
                ],
                @"messages": @[
                    @{@"role": @"system", @"content": @"You are Zed coding agent.\n- `/Volumes/SSD4T/pro/test`\n"},
                    @{@"role": @"user", @"content": @"旧问题"},
                    @{@"role": @"assistant", @"content": @"用 AI 写音乐主要有两种方式：Suno 和 Lyria…"},
                    @{@"role": @"user", @"content":
                          @"[@hello.py](file:///Volumes/SSD4T/pro/test/hello.py) 帮我修改输出为中文\n"
                          @"<files>\n```py /Volumes/SSD4T/pro/test/hello.py\nprint(\"Hello, World!\")\n```\n</files>"}
                ]
            };
            NSString *p = [AIBridgeToolSimulator buildWebpagePromptFromRequest:polluted];
            expect(![p containsString:@"Suno"], "music prose filtered from prompt");
            expect(![p containsString:@"写音乐"], "music topic filtered");
            expect([p containsString:@"hello.py"], "coding task kept");
            expect(![p containsString:@"You are the Zed coding agent"], "IDE long system dropped");
            expect([p containsString:@"Project roots:"], "synthetic short system present");
            expect(![p containsString:@"Latest user task"], "no duplicated latest-task section");
            expect(![p containsString:@"up-to-date and don't need to be re-read"], "attachment boilerplate stripped");
            // 压缩后应显著短于旧版（旧版常 >8k 仅 system+tools）
            expect(p.length < 8000, "compact prompt for simple edit task");
        }

        // Huge IDE tool schemas must NOT wipe user file context from the prompt
        {
            NSMutableArray *fatTools = [NSMutableArray array];
            for (int i = 0; i < 20; i++) {
                NSString *name = [NSString stringWithFormat:@"tool_%d", i];
                NSMutableString *desc = [NSMutableString stringWithString:@"Long description. "];
                for (int j = 0; j < 80; j++) {
                    [desc appendFormat:@"<example>copy path %d/%d with lots of detail about directories and files</example> ", i, j];
                }
                [fatTools addObject:@{
                    @"type": @"function",
                    @"function": @{
                        @"name": name,
                        @"description": desc,
                        @"parameters": @{
                            @"type": @"object",
                            @"properties": @{
                                @"path": @{
                                    @"type": @"string",
                                    @"description": [desc copy]
                                },
                                @"edits": @{
                                    @"type": @"array",
                                    @"items": @{
                                        @"type": @"object",
                                        @"properties": @{
                                            @"old_text": @{@"type": @"string", @"description": [desc copy]},
                                            @"new_text": @{@"type": @"string", @"description": [desc copy]}
                                        }
                                    }
                                }
                            },
                            @"required": @[@"path"]
                        }
                    }
                }];
            }
            NSString *userTask =
                @"[@hello.py](file:///Volumes/SSD4T/pro/test/hello.py) 帮我修改这个文件，把它的输出改成中文\n"
                @"<context>\n<files>\n```py /Volumes/SSD4T/pro/test/hello.py\n"
                @"print(\"Hello, World!\")\n```\n</files>\n</context>";
            NSDictionary *fatReq = @{
                @"tools": fatTools,
                @"messages": @[
                    @{@"role": @"system", @"content": @"You are a coding agent."},
                    @{@"role": @"user", @"content": userTask}
                ]
            };
            NSString *p = [AIBridgeToolSimulator buildWebpagePromptFromRequest:fatReq];
            expect([p containsString:@"hello.py"], "fat tools still keep hello.py");
            expect([p containsString:@"Hello, World!"], "fat tools still keep file body");
            expect([p containsString:@"改成中文"], "fat tools still keep user task");
            expect([p containsString:@"## Messages"], "messages section present");
            // tools should be compact — full <example> spam should be gone or rare
            NSUInteger exampleCount = 0;
            NSRange search = NSMakeRange(0, p.length);
            while (search.location < p.length) {
                NSRange found = [p rangeOfString:@"<example>" options:0 range:search];
                if (found.location == NSNotFound) {
                    break;
                }
                exampleCount++;
                search.location = found.location + found.length;
                search.length = p.length - search.location;
            }
            expect(exampleCount < 5, "tool examples stripped from prompt");
            expect(p.length <= [AIBridgeToolSimulator maxPromptChars] + 40, "within budget");
        }

        if (gFailures) {
            printf("\n%d failure(s)\n", gFailures);
            return 1;
        }
        printf("\nall passed\n");
        return 0;
    }
}
