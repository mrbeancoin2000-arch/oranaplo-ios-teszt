import { withSupabase } from 'npm:@supabase/server@^1'
import { parseSafeReport, makeSafeEmail } from './policy.mjs'

/**
 * Privacy-first bug report. The request is authenticated by Supabase Auth.
 * The body is allowlisted; any additional fields are discarded and never sent.
 * A unique (user, UTC day) quota reduces abuse. CAPTCHA/rate limiting is still
 * required on anonymous Supabase Auth signups to prevent sybil spam.
 */
const respond = (status: number, code: string) => Response.json({ code }, { status })

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return respond(405, 'method_not_allowed')
    const userID = ctx.userClaims?.sub
    if (!userID) return respond(401, 'unauthenticated')
    const key = Deno.env.get('RESEND_API_KEY')
    const sender = Deno.env.get('REPORT_FROM_EMAIL')
    const recipient = Deno.env.get('REPORT_TO_EMAIL')
    if (!key || !sender || !recipient) return respond(503, 'not_configured')
    const raw = await req.text()
    if (raw.length > 1500) return respond(413, 'payload_too_large')
    const report = parseSafeReport(raw)
    if (!report) return respond(400, 'invalid_fields')

    const day = new Date().toISOString().slice(0, 10)
    const { error: quotaError } = await ctx.supabase
      .from('oranaplo_report_daily')
      .insert({ user_id: userID, day_utc: day })
    if (quotaError) {
      // Fail closed on SQL errors; do not risk spam if the quota table is missing.
      return respond(quotaError.code === '23505' ? 429 : 503, 'report_limit_or_unavailable')
    }
    // The server creates the email from validated fields only. No request body
    // is echoed; no arbitrary note, account info, health record or coordinates.
    const text = makeSafeEmail(report, day)

    try {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: sender, to: [recipient], subject: '[ÓraNapló] Hibabejelentés', text })
      })
      if (!response.ok) throw new Error('mail_provider_error')
      return respond(202, 'accepted')
    } catch {
      // If mail delivery failed, release the quota reservation for a retry.
      await ctx.supabaseAdmin.from('oranaplo_report_daily')
        .delete().eq('user_id', userID).eq('day_utc', day)
      return respond(502, 'delivery_failed')
    }
  })
}
