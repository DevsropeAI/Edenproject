# Eden Marketplace

Eden uses one Flutter app for customers and contractors, a Node.js API backed by MySQL, and a separate Next.js admin panel.

## Run locally

Use Node.js 24 or later, MySQL 8, and Flutter 3.47 or later with Dart 3.13.7 or later within Dart 3. Run the commands from this repository's root in PowerShell.

Create an empty MySQL database named `eden` with the `utf8mb4` character set. Give the API database user permission to create tables and read and write data in that database. The API creates its tables on startup.

### API

```powershell
$env:EDEN_MYSQL_URL = 'mysql://eden_user:your_password@127.0.0.1:3306/eden'
$env:EDEN_ADMIN_KEY = '<your random admin API key>'
$env:EDEN_ORIGINS = 'http://localhost:8080'
npm --prefix backend ci
npm --prefix backend start
```

The API listens on port 3001. URL-encode special characters in the MySQL username or password. Add `?tls=true` to require a verified TLS connection to a remote MySQL server.

### Flutter

```powershell
flutter pub get
flutter run -d chrome --web-port 8080
```

Chrome uses localhost and the Android emulator uses `10.0.2.2`. To connect an Android device on your development network, set `$env:HOST = '0.0.0.0'` before starting the API and launch the app with `--dart-define=EDEN_API_URL=http://<computer-LAN-IP>:3001/api`. Use an HTTPS API URL for release builds.

Register as a customer or contractor and sign in. Switch modes under **Profile & settings**. First-time contractor setup asks for a service area and a primary service. To try the job handoff, use separate accounts. The contractor can accept the customer's booking and submit work photos for approval. Booking and chat updates are fetched every 12 seconds while signed in.

### Next.js admin

Open a separate terminal and use the same API key you set for the backend.

```powershell
$env:EDEN_ADMIN_KEY = '<same admin API key>'
$env:EDEN_ADMIN_PASSWORD = '<your admin password>'
npm --prefix admin ci
npm --prefix admin run dev
```

Open `http://localhost:3000` and sign in as `admin` using the password above. Set the admin server's `EDEN_API_URL` if the API runs elsewhere. Serve the admin site over HTTPS if exposing it beyond local development.

## Client walkthrough

Open the Flutter web app in two separate browser profiles so the customer and contractor sessions stay independent. Open the Next.js admin panel in another tab. All three views use the same MySQL database through the Node.js API.

1. Register a customer and a contractor. Upload sample identification and insurance images in the contractor account, then approve them in **Admin → Verification**.
2. In customer mode, save a property with a map pin and place a booking. Confirm it appears in **Admin → Orders**.
3. In contractor mode, accept the booking, open the property pin, then mark the job **On the way**. Tap **Share live location** and grant permission. Keep that screen open. On the customer booking screen, the OpenStreetMap marker updates as new positions arrive.
4. Mark the job **Arrived**, upload before and after photos, and submit the work. Use the customer screen to approve and review it. Send a support request and resolve it in the admin panel.
5. Use **Profile & settings** to show how a single account switches between customer and contractor mode. Use distinct accounts for the booking handoff.

GPS sharing needs location permission and a secure context on the web. Use localhost for a desktop preview or HTTPS for a remote web demo. The browser may return a coarse position on a desktop. OpenStreetMap tiles need internet access and no Google Maps key.

## Optional integrations

Set `EDEN_SMTP_URL` and `EDEN_EMAIL_FROM` on the API server to enable password reset email. Set `TWILIO_VERIFY_SERVICE_SID`, `TWILIO_API_KEY` and `TWILIO_API_SECRET` to require SMS verification during registration. With SMS enabled, enter a phone number including its country code. An unset Twilio configuration keeps local registration available.

Set `EDEN_ENABLE_WEEKLY_ORDERS=true` on the API server to create future weekly orders for active preferences on completed bookings. The scheduler checks every minute and creates each occurrence at most once within 24 hours of its scheduled time. It uses the current service price and skips disabled services and removed properties. Orders are created without collecting a payment.

Contractors submit identification and insurance under Profile & settings. Review and approve both documents in the admin Verification tab before the contractor accepts a booking. Uploading replacement documents requires a new review. The admin Services tab controls service availability and base prices.

Set `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` and `EDEN_PAYMENT_RETURN_URL` to enable card payments for completed bookings. The return URL must use HTTPS. Register `/api/payments/webhook` as a Stripe webhook for `checkout.session.completed`, `refund.created`, `refund.updated` and `refund.failed`. Customers pay or tip from **Profile & settings → Payments & refunds**. Admins review refund requests in **Payments**. Use test-mode credentials for local verification.

## Coverage

MySQL stores accounts, sessions, support requests, properties, bookings, work photos, messages, reviews, uploaded profile and verification images, and account preferences. Admins can review orders, cancel open bookings, block accounts, and resolve support requests.

Bookings are placed without an upfront payment. Stripe Checkout and refund review are available when configured. Contractor payouts, push notifications and weather-triggered dispatch remain pending. Foreground GPS sharing updates the customer's booking map while the assigned contractor is en route. The customer view hides inactive locations after 30 seconds. Weekly pause/resume and snowfall preferences are saved.

Run `npm --prefix backend test` for booking logic tests. To include the MySQL integration suite, set `EDEN_MYSQL_TEST_URL` to a dedicated MySQL test database before running the command. Run `npm --prefix admin run build` to verify the admin build.
