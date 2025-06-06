# Deployment Execution Guide

## 🚀 Authentication Flow Enhancement - Deployment Steps

**Ready to Deploy**: Enhanced email confirmation flow with proper user sync  
**Estimated Time**: 15-30 minutes  
**Risk Level**: Low (backwards compatible, rollback available)

---

## 📋 Pre-Deployment Checklist

### ✅ Completed Preparations
- [x] **Code Quality**: Core authentication tests passing
- [x] **Documentation**: Deployment guides created
- [x] **Production Environment**: Configuration verified
- [x] **Rollback Plan**: Documented and ready

### 🔍 Final Verification Required

**Before proceeding, verify:**

1. **Fly.io Access**:
   ```bash
   fly auth login
   fly apps list | grep eventasaurus
   ```

2. **Environment Variables**:
   ```bash
   fly secrets list --app eventasaurus
   ```
   Required: `SECRET_KEY_BASE`, `SUPABASE_URL`, `SUPABASE_API_KEY`, `SUPABASE_DATABASE_URL`

3. **Supabase Configuration**:
   - Site URL: `https://eventasaur.us` (or your production domain)
   - Redirect URLs: Include `https://eventasaur.us/auth/callback`
   - Email confirmation: Enabled

---

## 🎯 Deployment Strategy: Controlled Rollout

### Phase 1: Backup & Preparation (5 minutes)

1. **Create Version Tag**:
   ```bash
   git add .
   git commit -m "feat: enhanced authentication flow with email confirmation"
   git tag v1.0.0-auth-enhancement
   git push origin main
   git push origin v1.0.0-auth-enhancement
   ```

2. **Backup Current State**:
   ```bash
   # Note current deployment
   fly status --app eventasaurus
   fly releases --app eventasaurus | head -5
   ```

### Phase 2: Deploy Application (10 minutes)

1. **Compile Assets**:
   ```bash
   mix assets.deploy
   ```

2. **Deploy to Production**:
   ```bash
   fly deploy --app eventasaurus --wait-timeout 300
   ```

3. **Monitor Deployment**:
   ```bash
   # Watch deployment progress
   fly logs --app eventasaurus --follow
   ```

### Phase 3: Verification & Testing (10 minutes)

1. **Health Check**:
   ```bash
   curl -I https://eventasaur.us/
   # Should return 200 OK
   ```

2. **Authentication Endpoints**:
   ```bash
   curl -I https://eventasaur.us/auth/callback
   # Should return 200 or redirect (not 500)
   ```

3. **Manual Testing**:
   - Visit a public event page (e.g., `https://eventasaur.us/{event-slug}`)
   - Try registering with a real email address
   - Verify email confirmation flow works
   - Check that existing users can still register immediately

### Phase 4: Monitor & Validate (5 minutes)

1. **Check Application Logs**:
   ```bash
   fly logs --app eventasaurus | grep -E "(ERROR|WARN|auth|registration)"
   ```

2. **Verify Database Connectivity**:
   ```bash
   fly ssh console --app eventasaurus
   # In the console:
   # /app/bin/eventasaurus remote
   # EventasaurusApp.Repo.query("SELECT 1")
   ```

---

## 🧪 Post-Deployment Testing

### Critical Path Testing

**Test 1: New User Registration**
1. Go to any public event page
2. Click "Register for Event"
3. Enter a real email address
4. Verify "Check your email" message appears
5. Check email and click confirmation link
6. Verify successful registration and redirect

**Test 2: Existing User Registration**
1. Use an email that already has an account
2. Register for an event
3. Should see immediate success (no email required)

**Test 3: Error Handling**
1. Try invalid email format
2. Try registering for non-existent event
3. Verify appropriate error messages

### Performance Verification

```bash
# Check response times
curl -w "@curl-format.txt" -o /dev/null -s https://eventasaur.us/

# Monitor resource usage
fly status --app eventasaurus
fly metrics --app eventasaurus
```

---

## 🚨 Rollback Procedures

### Immediate Rollback (< 2 minutes)

If critical issues are detected:

```bash
# Option 1: Rollback via Fly.io
fly releases --app eventasaurus
fly releases rollback <previous-version> --app eventasaurus

# Option 2: Deploy previous version
git checkout v1.0.0-pre-auth-enhancement
fly deploy --app eventasaurus --wait-timeout 300
```

### Configuration Rollback

If Supabase configuration needs reverting:

1. **Supabase Dashboard**:
   - Authentication → Settings → Site URL (revert)
   - Authentication → Settings → Redirect URLs (remove new URLs)
   - Authentication → Templates (revert email templates)

2. **Environment Variables** (if changed):
   ```bash
   fly secrets set SUPABASE_URL=<previous-url> --app eventasaurus
   ```

---

## 📊 Success Criteria

### Technical Metrics
- [ ] **Deployment**: Completes without errors
- [ ] **Health Check**: Returns 200 OK
- [ ] **Database**: Connections working
- [ ] **Authentication**: Login/logout functional
- [ ] **Email Flow**: Confirmation emails delivered

### User Experience Metrics
- [ ] **New Users**: Can register and receive confirmation emails
- [ ] **Existing Users**: Can register immediately without email
- [ ] **Error Handling**: Appropriate messages for edge cases
- [ ] **Performance**: Response times < 2 seconds

---

## 🔍 Monitoring Commands

### Real-time Monitoring
```bash
# Application logs
fly logs --app eventasaurus --follow

# Application status
watch -n 30 'fly status --app eventasaurus'

# Error monitoring
fly logs --app eventasaurus | grep -E "(ERROR|CRITICAL|FATAL)"
```

### Health Checks
```bash
# Basic connectivity
curl -f https://eventasaur.us/ || echo "Site down"

# Authentication endpoints
curl -f https://eventasaur.us/auth/callback || echo "Auth endpoint issue"

# Database health (via app console)
fly ssh console --app eventasaurus -C "/app/bin/eventasaurus eval 'EventasaurusApp.Repo.query(\"SELECT 1\")'"
```

---

## 📞 Emergency Response

### If Deployment Fails
1. **Check logs**: `fly logs --app eventasaurus`
2. **Verify configuration**: `fly secrets list --app eventasaurus`
3. **Rollback immediately**: Use rollback procedures above
4. **Investigate**: Review error messages and fix issues

### If Authentication Breaks
1. **Immediate rollback**: Deploy previous version
2. **Check Supabase**: Verify service status and configuration
3. **Test locally**: Reproduce issue in development
4. **Hotfix**: Apply minimal fix and redeploy

### If Email Delivery Fails
1. **Check Supabase**: Authentication → Settings → SMTP
2. **Verify templates**: Authentication → Templates
3. **Test manually**: Send test email from Supabase dashboard
4. **Fallback**: Temporarily disable email confirmation if critical

---

## ✅ Deployment Completion

Once all tests pass and monitoring shows stable operation:

1. **Update Documentation**:
   - Mark deployment as complete in this guide
   - Update any relevant user documentation
   - Record lessons learned

2. **Notify Stakeholders**:
   - Confirm successful deployment
   - Share any relevant metrics or observations
   - Schedule follow-up monitoring

3. **Clean Up**:
   - Remove any temporary debugging
   - Archive deployment logs
   - Plan next iteration improvements

---

**Deployment Date**: ________________  
**Deployed By**: ________________  
**Rollback Tested**: ☐ Yes ☐ No  
**Success Criteria Met**: ☐ Yes ☐ No  
**Sign-off**: ________________ 