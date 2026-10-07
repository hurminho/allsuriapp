/// <reference types="node" />
// import { createClient } from "@supabase/supabase-js"; // ✅ 제거
import { randomBytes } from 'crypto'

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string

export const handler = async (event: any) => {
  try {
    if (event.httpMethod !== 'POST') {
      return { statusCode: 405, body: JSON.stringify({ message: 'Method Not Allowed' }), headers: { 'Content-Type': 'application/json' } };
    }
    const body = JSON.parse(event.body || '{}')
    const accessToken = body.access_token as string | undefined
    if (!accessToken) {
      return { statusCode: 400, body: JSON.stringify({ message: 'access_token is required' }), headers: { 'Content-Type': 'application/json' } };
    }

    // Validate Kakao token and get profile
    const me = await fetch('https://kapi.kakao.com/v2/user/me', {
      headers: { Authorization: `Bearer ${accessToken}` },
    })
    if (!me.ok) {
      const t = await me.text()
      return { statusCode: 401, body: JSON.stringify({ message: 'Invalid Kakao token', detail: t }), headers: { 'Content-Type': 'application/json' } };
    }
    const kakao = await me.json()
    const kakaoId = String(kakao.id)
    const account = kakao.kakao_account || {}
    const profile = account.profile || {}
    
    // 카카오에서 제공하는 모든 정보 수집
    const email = account.email || '';
    let userId: string = ''; // userId를 let으로 단일 선언
    const name = profile.nickname || '카카오 사용자';
    const profileImage = profile.profile_image_url || profile.thumbnail_image_url || '';
    const phoneNumber = account.phone_number ? account.phone_number.replace(/\+82\s?/, '0').replace(/\s|-/g, '') : '';
    const ageRange = account.age_range || '';
    const birthday = account.birthday || '';
    const gender = account.gender || '';
    
    console.log('📱 카카오 사용자 정보 수집:', {
      kakaoId,
      name,
      email,
      hasProfileImage: !!profileImage,
      hasPhone: !!phoneNumber,
      ageRange,
      gender
    })

    // Persist/find user in Supabase (service role), prefer returning UUID id
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      const localId = `kakao:${kakaoId}`;
      // issueJwt 제거 및 에러 반환
      return new Response(JSON.stringify({ success: false, message: 'Supabase 환경 변수 누락', error: 'SUPABASE_ENV_MISSING' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    let externalId = `kakao:${kakaoId}`
    const nowIso = new Date().toISOString()
    
    // Supabase Auth Admin API를 위한 정규화된 이메일 주소
    const supabaseAuthEmail = email && email.includes('@') && !email.includes('@example.local')
      ? email
      : `kakao-${kakaoId}@allsuri.app`;

    let supabaseAccessToken: string | null = null;
    let supabaseRefreshToken: string | null = null;
    // Supabase Auth 비밀번호는 로그인할 때마다 새로 만든 난수입니다. 토큰 발급에만 쓰고 저장하지 않습니다.
    // (예전에는 카카오 회원번호를 그대로 비밀번호로 써서, 회원번호만 알면 누구나 로그인할 수 있었습니다.)
    const sessionPassword = randomBytes(32).toString('base64url')
    
    console.log('[Kakao Login] 🔐 Step 1: Supabase Auth 처리 시작');
    console.log(`   - SUPABASE_URL: ${SUPABASE_URL ? '설정됨' : '❌ 없음'}`);
    console.log(`   - SUPABASE_SERVICE_ROLE_KEY: ${SUPABASE_SERVICE_ROLE_KEY ? '설정됨' : '❌ 없음'}`);
    console.log(`   - User Email (for Supabase Auth): ${supabaseAuthEmail}`);
    
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      console.error('❌ [Kakao Login] Supabase 환경 변수 누락!');
      return { statusCode: 500, body: JSON.stringify({ success: false, message: 'Supabase 환경 변수 누락', error: 'SUPABASE_ENV_MISSING' }), headers: { 'Content-Type': 'application/json' } };
    }
    
    // STEP 1: Supabase Auth 사용자 확인/생성 (UUID 확보)
    let authUserId: string | null = null;
    let existingUser: any | null = null; // 전역 스코프로 이동
    
    try {
      // 1-1. users 테이블에서 kakao_id로 먼저 조회 (가장 정확한 식별자)
      console.log(`🔍 [Kakao Login] Step 1-1: kakao_id로 users 테이블 조회 중...`);
      console.log(`   - Kakao ID: ${kakaoId}`);
      try {
        const usersCheckUrl = `${SUPABASE_URL}/rest/v1/users?kakao_id=eq.${kakaoId}&select=id,email,kakao_id,name`;
        console.log(`   - Users Table URL: ${usersCheckUrl}`);
        const usersCheckRes = await fetch(usersCheckUrl, {
          headers: { 
            apikey: SUPABASE_SERVICE_ROLE_KEY, 
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` 
          },
        });
        
        if (usersCheckRes.ok) {
          const usersData = await usersCheckRes.json();
          console.log(`🔍 [Kakao Login] users 테이블 조회 응답:`, JSON.stringify(usersData));
          
          if (Array.isArray(usersData) && usersData.length > 0) {
            existingUser = usersData[0];
            authUserId = existingUser.id;
            console.log(`✅ [Kakao Login] users 테이블에서 기존 사용자 발견: ${authUserId}`);
            console.log(`   - Name: ${existingUser.name}`);
            console.log(`   - Email: ${existingUser.email}`);
          } else {
            console.log('🔍 [Kakao Login] users 테이블에 kakao_id로 사용자 없음.');
          }
        } else {
          console.log(`⚠️ [Kakao Login] users 테이블 조회 실패 (HTTP ${usersCheckRes.status}): ${await usersCheckRes.text()}`);
        }
      } catch (e: any) {
        console.log(`❌ [Kakao Login] users 테이블 조회 중 에러: ${e.message}`);
      }
      
      // 1-2. Supabase Auth 사용자 확인 (authUserId가 있으면 해당 ID로 조회)
      let existingSupabaseUser: { id: string; email: string; user_metadata?: any } | null = null;
      let userAlreadyExists = false;

      try {
        if (authUserId) {
          // authUserId가 있으면 ID로 직접 조회
          const authCheckByIdUrl = `${SUPABASE_URL}/auth/v1/admin/users/${authUserId}`;
          console.log(`   - Auth Admin URL (Check by ID): ${authCheckByIdUrl}`);
          const checkByIdRes = await fetch(authCheckByIdUrl, {
            method: 'GET',
            headers: {
              apikey: SUPABASE_SERVICE_ROLE_KEY,
              Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            },
          });

          if (checkByIdRes.ok) {
            existingSupabaseUser = await checkByIdRes.json();
            userAlreadyExists = true;
            console.log(`✅ [Kakao Login] Supabase Auth 사용자 존재 확인 (ID: ${authUserId})`);
            
            // user_metadata에 kakao_id가 있는지 확인
            const userMetadata = existingSupabaseUser?.user_metadata || {};
            if (userMetadata.kakao_id !== kakaoId) {
              console.warn(`⚠️ [Kakao Login] user_metadata의 kakao_id가 다릅니다! (저장된: ${userMetadata.kakao_id}, 현재: ${kakaoId})`);
            }
          } else {
            console.log(`⚠️ [Kakao Login] Supabase Auth 사용자 없음 (ID: ${authUserId}). 새로 생성 필요.`);
            authUserId = null; // Auth에 없으므로 새로 생성
          }
        } else {
          console.log('🔍 [Kakao Login] users 테이블에 사용자가 없으므로 새로 생성합니다.');
        }
      } catch (e: any) {
        console.log(`❌ [Kakao Login] Supabase Auth 사용자 확인 중 에러 발생: ${e.message}`);
      }

      // 1-2. Supabase Auth 사용자 생성 (존재하지 않는 경우)
      if (!userAlreadyExists) {
        console.log('[Kakao Login] Step 1-2: Supabase Auth 사용자 생성 시도 중...');
        const createUserUrl = `${SUPABASE_URL}/auth/v1/admin/users`;
        console.log(`   - Create User URL: ${createUserUrl}`);
        const createUserBody = {
          email: supabaseAuthEmail,
          password: sessionPassword,
          email_confirm: true,
          user_metadata: {
            email_verified: true,
            kakao_id: kakaoId,
            name: name,
            provider: 'kakao',
          },
        };

        const createUserRes = await fetch(createUserUrl, {
          method: 'POST',
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(createUserBody),
        });

        if (!createUserRes.ok) {
          const errorText = await createUserRes.text();
          console.warn(`[Kakao Login] Supabase Auth 사용자 생성 실패: ${errorText}`);
          
          // email_exists 오류인 경우, kakao_id로 다시 조회
          try {
            const errorData = JSON.parse(errorText);
            if (errorData.error_code === 'email_exists') {
              console.log('🔄 [Kakao Login] email_exists 오류 감지. kakao_id로 기존 사용자 재조회 시도...');
              
              // users 테이블에서 kakao_id로 재조회
              const retryUsersCheckRes = await fetch(`${SUPABASE_URL}/rest/v1/users?kakao_id=eq.${kakaoId}&select=id`, {
                headers: { 
                  apikey: SUPABASE_SERVICE_ROLE_KEY, 
                  Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` 
                },
              });
              
              if (retryUsersCheckRes.ok) {
                const retryUsersData = await retryUsersCheckRes.json();
                console.log(`🔍 [Kakao Login] users 테이블 재조회 응답:`, JSON.stringify(retryUsersData));
                
                if (Array.isArray(retryUsersData) && retryUsersData.length > 0) {
                  const foundUser = retryUsersData[0];
                  authUserId = foundUser.id;
                  
                  // Supabase Auth에서도 해당 사용자 확인
                  const retryAuthCheckRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${authUserId}`, {
                    method: 'GET',
                    headers: {
                      apikey: SUPABASE_SERVICE_ROLE_KEY,
                      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
                    },
                  });
                  
                  if (retryAuthCheckRes.ok) {
                    existingSupabaseUser = await retryAuthCheckRes.json();
                    userAlreadyExists = true;
                    console.log(`✅ [Kakao Login] kakao_id로 재조회 성공! 사용자 ID: ${authUserId}`);
                  }
                }
              }
            }
          } catch (parseError) {
            console.log(`⚠️ [Kakao Login] 오류 응답 파싱 실패:`, parseError);
          }
          
          // 재조회에도 실패한 경우에만 에러 반환
          if (!userAlreadyExists) {
            return { statusCode: 500, body: JSON.stringify({
              success: false,
              message: 'Supabase Auth 사용자 생성 실패',
              error: errorText,
            }), headers: { 'Content-Type': 'application/json' } };
          }
        } else {
          const createUserData = await createUserRes.json();
          authUserId = createUserData.id;
          console.log(`✅ [Kakao Login] Supabase Auth 사용자 생성 완료: ${authUserId}`);
        }
      }

      if (userAlreadyExists && existingSupabaseUser && authUserId) {
        // 기존 사용자(재조회로 찾은 경우 포함)의 비밀번호를 이번 로그인용 난수로 바꿉니다 (password grant 로그인을 위해)
        console.log(`🔄 [Kakao Login] Step 1-3: 기존 사용자 비밀번호 업데이트 시도...`);
        const updateUserUrl = `${SUPABASE_URL}/auth/v1/admin/users/${authUserId}`;
        const updateUserBody: Record<string, any> = {
          password: sessionPassword
        };
        
        if (existingSupabaseUser.email !== supabaseAuthEmail) {
          console.log(`⚠️ [Kakao Login] 기존 사용자 이메일(${existingSupabaseUser.email})도 업데이트합니다.`);
          updateUserBody.email = supabaseAuthEmail;
        }
        
        const updateRes = await fetch(updateUserUrl, {
          method: 'PUT',
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(updateUserBody),
        });

        if (updateRes.ok) {
          console.log(`✅ [Kakao Login] 사용자 정보 업데이트 완료 (비밀번호 & 이메일)`);
        } else {
          const errText = await updateRes.text();
          console.warn(`❌ [Kakao Login] 사용자 정보 업데이트 실패: ${errText}`);
          return { statusCode: 500, body: JSON.stringify({ success: false, message: 'Supabase Auth 사용자 갱신 실패', error: errText }), headers: { 'Content-Type': 'application/json' } };
        }
      }
      
      if (!authUserId) {
        return { statusCode: 500, body: JSON.stringify({ success: false, message: 'Supabase Auth 사용자 ID를 확보하지 못했습니다' }), headers: { 'Content-Type': 'application/json' } };
      }

      console.log(`✅ [Kakao Login] Step 1 완료! Auth User ID: ${authUserId}`);

      // 1-3. 토큰 생성
      console.log('[Kakao Login] Step 1-4: 토큰 생성 중 (password grant)...');
      const tokenUrl = `${SUPABASE_URL}/auth/v1/token?grant_type=password`;
      const tokenBody = {
        email: supabaseAuthEmail,
        password: sessionPassword,
      };

      const tokenRes = await fetch(tokenUrl, {
        method: 'POST',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(tokenBody),
      });
      
      console.log(`   - 응답 상태: ${tokenRes.status} ${tokenRes.statusText}`);
      
      if (tokenRes.ok) {
        const tokenData = await tokenRes.json();
        supabaseAccessToken = tokenData.access_token || null;
        supabaseRefreshToken = tokenData.refresh_token || null;
        console.log('[Kakao Login] ✅ Supabase 세션 토큰 생성 성공');
        // 토큰 값은 일부라도 로그에 남기지 않습니다(리프레시 토큰은 20자 안팎이라 통째로 노출됨).
        console.log(`   - Access Token: ${supabaseAccessToken ? '있음' : '❌ 없음'}`);
        console.log(`   - Refresh Token: ${supabaseRefreshToken ? '있음' : '❌ 없음'}`);
      } else {
        const errText = await tokenRes.text();
        console.error('[Kakao Login] ❌ Supabase 토큰 생성 실패');
        console.error(`   - 상태: ${tokenRes.status}`);
        console.error(`   - 에러: ${errText}`);
        return { statusCode: 500, body: JSON.stringify({ success: false, message: 'Supabase 토큰 생성 실패', error: errText }), headers: { 'Content-Type': 'application/json' } };
      }
    } catch (authErr: any) {
      console.error('[Kakao Login] ❌ Supabase Auth 처리 오류:', authErr.message);
      console.error(`   - 스택:`, authErr.stack);
      return { statusCode: 500, body: JSON.stringify({ success: false, message: 'Supabase Auth 처리 오류', error: authErr.message }), headers: { 'Content-Type': 'application/json' } };
    }
    
    // STEP 2: users 테이블 처리 (authUserId를 사용하여 일관성 보장)
    console.log('[Kakao Login] 🗄️ Step 2: users 테이블 처리 시작');
    console.log(`   - Auth User ID: ${authUserId}`);
    
    let row: any | null = existingUser; // Step 1-1에서 이미 조회한 사용자 재사용
    try {
      // 2-1. existingUser가 없으면 authUserId로 다시 조회 (혹시 모를 경우 대비)
      if (!row && authUserId) {
        console.log('[Kakao Login] Step 2-1: users 테이블 재조회 중...');
        const r = await fetch(`${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(authUserId)}&select=*`, {
          headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` },
        });
        const arr = await r.json();
        if (Array.isArray(arr) && arr.length > 0) {
          row = arr[0];
          console.log(`✅ [Kakao Login] users 테이블에 이미 존재: ${row.id}`);
        }
      } else if (row) {
        console.log(`✅ [Kakao Login] users 테이블 레코드 이미 조회됨: ${row.id}`);
      }
      
      // 2-2. users 테이블에 없으면 생성 (authUserId를 id로 사용)
      if (!row) {
        console.log('[Kakao Login] Step 2-2: users 테이블에 새 레코드 생성 중...');
        const payload: Record<string, any> = {
          id: authUserId, // ✅ Supabase Auth ID를 그대로 사용!
          email: supabaseAuthEmail,
          name,
          role: 'customer',
          createdat: nowIso,
          provider: 'kakao',
          external_id: externalId,
          kakao_id: kakaoId,
          profile_image: profileImage,
          phonenumber: phoneNumber || null,
          age_range: ageRange || null,
          birthday: birthday || null,
          gender: gender || null,
        };

        const ins = await fetch(`${SUPABASE_URL}/rest/v1/users`, {
          method: 'POST',
          headers: { 
            apikey: SUPABASE_SERVICE_ROLE_KEY, 
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`, 
            'Content-Type': 'application/json', 
            Prefer: 'return=representation' 
          },
          body: JSON.stringify(payload),
        });
        
        if (ins.ok) {
          const arr = await ins.json();
          row = Array.isArray(arr) ? arr[0] : arr;
          console.log('✅ [Kakao Login] users 테이블 레코드 생성 성공:', row?.id);
        } else {
          const errText = await ins.text();
          console.error('❌ [Kakao Login] users 테이블 레코드 생성 실패:', ins.status, errText);
          // 실패해도 계속 진행 (Auth는 이미 생성됨)
        }
      } else {
        // 2-3. users 테이블 업데이트 (최신 카카오 정보 반영)
        console.log('[Kakao Login] Step 2-3: users 테이블 업데이트 중...');
        const updatePayload: Record<string, any> = {
          name,
        };
        
        if (profileImage) {
          updatePayload.profile_image = profileImage;
        }
        
        if (phoneNumber && !row.phonenumber) {
          updatePayload.phonenumber = phoneNumber;
        }
        
        if (!row.kakao_id) {
          updatePayload.kakao_id = kakaoId;
        }
        
        if (Object.keys(updatePayload).length > 0) {
          const upd = await fetch(`${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(row.id)}`, {
            method: 'PATCH',
            headers: {
              apikey: SUPABASE_SERVICE_ROLE_KEY,
              Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
              'Content-Type': 'application/json',
              Prefer: 'return=representation',
            },
            body: JSON.stringify(updatePayload),
          });
          
          if (upd.ok) {
            const updated = await upd.json();
            row = Array.isArray(updated) && updated.length > 0 ? updated[0] : row;
            console.log('✅ [Kakao Login] users 테이블 업데이트 성공:', row.id);
          }
        }
      }
    } catch (usersErr: any) {
      console.error('[Kakao Login] ❌ users 테이블 처리 오류:', usersErr.message);
      // users 테이블 처리 실패해도 계속 진행 (Auth는 성공했으므로)
    }
    
    userId = authUserId; // ✅ authUserId를 최종 userId로 사용
    const userRole = row?.role || 'customer';
    const businessStatus = row?.businessStatus || row?.businessstatus;
    
    console.log('[Kakao Login] ✅ 로그인 성공!');
    console.log(`   - User ID: ${userId}`);
    console.log(`   - Name: ${row?.name || name}`);
    console.log(`   - Role: ${userRole}`);
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: 'Kakao login successful',
        data: {
          user: {
            id: userId,
            name: row?.name || name,
            email: supabaseAuthEmail,
            role: userRole,
            businessStatus: businessStatus,
            external_id: row?.external_id || externalId,
          },
          supabase_access_token: supabaseAccessToken,
          supabase_refresh_token: supabaseRefreshToken,
        },
      }),
      headers: { 'Content-Type': 'application/json' },
    };
  } catch (e: any) {
    return { statusCode: 500, body: JSON.stringify({ message: 'Kakao login failed', error: String(e) }), headers: { 'Content-Type': 'application/json' } };
  }
}

