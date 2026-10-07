import type { Handler, HandlerEvent } from '@netlify/functions'

// AI 연결 상태 확인용. 키 값·접두사·길이와 환경변수 이름은 내려주지 않습니다
// (예전에는 키 앞 8자리와 OPEN·AI 가 들어간 환경변수 이름 목록을 공개로 반환했습니다).
const handler: Handler = async (event: HandlerEvent) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Content-Type': 'application/json',
  };

  // Handle preflight
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers, body: '' };
  }

  const useOpenAI = !!process.env.OPENAI_API_KEY;
  const useOpenRouter = !!process.env.OPENROUTER_API_KEY;
  const provider = useOpenAI ? 'openai' : useOpenRouter ? 'openrouter' : 'none';

  return {
    statusCode: 200,
    headers,
    body: JSON.stringify({ provider, configured: provider !== 'none' }),
  };
};

export { handler };
