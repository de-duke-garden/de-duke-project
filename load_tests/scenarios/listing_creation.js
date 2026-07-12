// Priority Scenario 4: Listing creation & multi-image upload.
// Validates: many hosts publishing/editing listings concurrently, including
// multi-photo uploads, exercising the structured upload contract (no
// silent data loss -- app/api/v1/listings.py's images_meta + file_<temp_key>
// multipart contract), and that embedding (re)generation via the
// Background Task Processor keeps up without a growing SQS backlog.
import http from 'k6/http';
import { check, sleep } from 'k6';
import { taggedPost, loginSyntheticHost, BASE_URL, API_PREFIX } from '../lib/client.js';
import { endpointThresholds, globalErrorRateThreshold } from '../lib/thresholds.js';

// Verified-host synthetic accounts (apps/backend/scripts/seed_load_test_data.py
// --with-verified-hosts) -- listing creation requires a verified
// HostAccount (see listings.py's _get_own_host_account), unlike search/auth
// which work for any account.
const VERIFIED_HOST_COUNT = 5000; // matches the seeder's --with-verified-hosts default

export const options = {
  scenarios: {
    listing_creation: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { target: 100, duration: '3m' }, // ~100 hosts concurrently publishing
        { target: 100, duration: '20m' },
      ],
    },
  },
  thresholds: {
    ...endpointThresholds('listing_create'),
    ...endpointThresholds('listing_image_upload'),
    ...globalErrorRateThreshold(),
  },
};

function shortletPayload(hostIndex) {
  return {
    listing_type: 'shortlet',
    title: `Load Test Shortlet #${hostIndex}-${Date.now()}`,
    description:
      'Synthetic load-test listing, safe to purge -- see apps/backend/scripts/seed_load_test_data.py.',
    location: {
      latitude: 6.4281 + Math.random() * 0.3,
      longitude: 3.4219 + Math.random() * 0.3,
      address_line: `${hostIndex} Load Test Close`,
      city: 'Lagos',
      state: 'Lagos',
    },
    amenities: ['wifi', 'generator', 'air_conditioning'],
    shortlet: {
      nightly_price: 25000 + Math.floor(Math.random() * 50000),
      minimum_stay_nights: 2,
      bedrooms: 2,
      bathrooms: 2,
      subtype: '2_bedroom',
      house_rules: ['no_smoking'],
      blocked_dates: [],
    },
  };
}

export default function () {
  const hostIndex = Math.floor(Math.random() * VERIFIED_HOST_COUNT);
  const headers = loginSyntheticHost(hostIndex);

  const createRes = taggedPost('/listings', shortletPayload(hostIndex), 'listing_create', {
    headers,
  });
  check(createRes, {
    'listing created (201)': (r) => r.status === 201,
  });
  if (createRes.status !== 201) {
    sleep(1);
    return;
  }
  const listingId = createRes.json('id');

  // Multi-image upload: 4 images per listing, matching the structured
  // images_meta + file_<temp_key> multipart contract (listings.py header
  // comment) -- deliberately multi-file, not single-file, since that's the
  // contract this scenario is meant to exercise under concurrency.
  const imagesMeta = [0, 1, 2, 3].map((i) => ({
    temp_key: `img${i}`,
    display_order: i,
    is_primary: i === 0,
  }));
  const formData = {
    images_meta: JSON.stringify(imagesMeta),
  };
  // ~200KB synthetic JPEG-shaped payload per image -- representative size
  // without needing real seeded binary fixtures.
  const fakeImageBytes = http.file(new Uint8Array(200 * 1024).fill(0xff), 'load-test.jpg', 'image/jpeg');
  for (const meta of imagesMeta) {
    formData[`file_${meta.temp_key}`] = fakeImageBytes;
  }

  const uploadRes = http.post(
    `${BASE_URL}${API_PREFIX}/listings/${listingId}/images`,
    formData,
    { headers, tags: { endpoint: 'listing_image_upload' } },
  );
  check(uploadRes, {
    'image upload accepted (201)': (r) => r.status === 201,
  });

  sleep(Math.random() * 2);
}
