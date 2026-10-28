/**
 * Adapter for Spike mock-chat.html
 * Load after runtime.js
 */
(function () {
  'use strict';
  if (!window.AIBridgeRuntime) {
    console.error('[AIBridge] runtime.js not loaded');
    return;
  }

  AIBridgeRuntime.install({
    id: 'mock',
    matchHosts: null,
    inputSelector: '#meo-bridge-input',
    sendSelector: '#meo-bridge-send',
    assistantSelector: '.meo-bridge-msg.assistant .body',
    busySelector: '#meo-bridge-busy',
    newChatSelector: '#meo-bridge-new',
    loggedIn: function () {
      return true;
    }
  });

  console.info('[AIBridge] mock adapter installed', __MeoAIBridge.probe());
})();
