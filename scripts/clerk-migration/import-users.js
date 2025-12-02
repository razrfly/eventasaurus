/**
 * Clerk User Import Script
 *
 * Imports users from Supabase export (users.json) into Clerk.
 * Preserves bcrypt password hashes and maps Supabase UUIDs to external_id.
 *
 * Usage:
 *   npm start           # Run import
 *   npm run dry-run     # Preview without importing
 *
 * Environment:
 *   CLERK_SECRET_KEY    # Your Clerk secret key (sk_test_... or sk_live_...)
 */

require('dotenv').config({ path: '../../.env' });

const fs = require('fs');
const path = require('path');

const CLERK_SECRET_KEY = process.env.CLERK_SECRET_KEY;
const DRY_RUN = process.env.DRY_RUN === 'true';
const RATE_LIMIT_MS = 100; // Clerk rate limit: 20 req/sec, we use 10 req/sec to be safe

if (!CLERK_SECRET_KEY) {
  console.error('Error: CLERK_SECRET_KEY environment variable is required');
  process.exit(1);
}

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function createUser(userData) {
  const payload = {
    external_id: userData.userId,
    email_address: [userData.email],
    first_name: userData.firstName || undefined,
    last_name: userData.lastName || undefined,
    password_hasher: userData.passwordHasher || 'bcrypt',
    password_digest: userData.password,
    skip_password_requirement: !userData.password,
  };

  // Remove undefined values
  Object.keys(payload).forEach(key => payload[key] === undefined && delete payload[key]);

  const response = await fetch('https://api.clerk.com/v1/users', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${CLERK_SECRET_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  const result = await response.json();

  if (!response.ok) {
    throw new Error(`Clerk API error: ${JSON.stringify(result)}`);
  }

  return result;
}

async function main() {
  console.log('='.repeat(60));
  console.log('Eventasaurus Clerk User Import');
  console.log('='.repeat(60));
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN (no changes)' : 'LIVE IMPORT'}`);
  console.log('');

  // Load users
  const usersPath = path.join(__dirname, 'users.json');
  if (!fs.existsSync(usersPath)) {
    console.error('Error: users.json not found. Run the export SQL first.');
    process.exit(1);
  }

  const users = JSON.parse(fs.readFileSync(usersPath, 'utf8'));
  console.log(`Found ${users.length} users to import`);
  console.log('');

  const results = {
    success: [],
    failed: [],
    skipped: [],
  };

  for (let i = 0; i < users.length; i++) {
    const user = users[i];
    const progress = `[${i + 1}/${users.length}]`;

    if (DRY_RUN) {
      console.log(`${progress} Would import: ${user.email} (${user.firstName} ${user.lastName})`);
      results.skipped.push(user);
      continue;
    }

    try {
      const clerkUser = await createUser(user);
      console.log(`${progress} ✓ Imported: ${user.email} -> ${clerkUser.id}`);
      results.success.push({ supabase: user, clerk: clerkUser });
      await sleep(RATE_LIMIT_MS);
    } catch (error) {
      console.error(`${progress} ✗ Failed: ${user.email} - ${error.message}`);
      results.failed.push({ user, error: error.message });
      await sleep(RATE_LIMIT_MS);
    }
  }

  // Summary
  console.log('');
  console.log('='.repeat(60));
  console.log('Import Summary');
  console.log('='.repeat(60));
  console.log(`Total:    ${users.length}`);
  console.log(`Success:  ${results.success.length}`);
  console.log(`Failed:   ${results.failed.length}`);
  console.log(`Skipped:  ${results.skipped.length}`);

  // Save results
  const resultsPath = path.join(__dirname, `import-results-${Date.now()}.json`);
  fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
  console.log(`\nResults saved to: ${resultsPath}`);

  if (results.failed.length > 0) {
    console.log('\nFailed users:');
    results.failed.forEach(({ user, error }) => {
      console.log(`  - ${user.email}: ${error}`);
    });
  }
}

main().catch(console.error);
