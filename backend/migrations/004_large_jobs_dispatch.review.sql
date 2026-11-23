-- REVIEW ONLY: NOT APPLIED. Local scratch verification and explicit approval
-- are required before application.
-- This migration adds dispatch state for large jobs. It does not modify
-- existing status columns or existing booking logic.

-- L1. DISPATCH STATE
ALTER TABLE bookings ADD COLUMN dispatch_status ENUM('open', 'pending_admin', 'assigned', 'rejected') NOT NULL DEFAULT 'open';
ALTER TABLE bookings ADD COLUMN assigned_contractor_id CHAR(64) NULL DEFAULT NULL;
ALTER TABLE bookings ADD COLUMN assigned_by_admin_id CHAR(64) NULL DEFAULT NULL;
ALTER TABLE bookings ADD COLUMN assigned_at DATETIME(6) NULL DEFAULT NULL;
ALTER TABLE bookings ADD COLUMN admin_note TEXT NULL DEFAULT NULL;
ALTER TABLE bookings ADD COLUMN rejection_reason TEXT NULL DEFAULT NULL;

-- Add indexes for the admin queue
CREATE INDEX idx_bookings_dispatch_status ON bookings (dispatch_status);
CREATE INDEX idx_bookings_assigned_contractor ON bookings (assigned_contractor_id);

-- Foreign keys
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_assigned_contractor FOREIGN KEY (assigned_contractor_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_assigned_admin FOREIGN KEY (assigned_by_admin_id) REFERENCES users(id) ON DELETE SET NULL;

-- Only after every preceding operation succeeds:
INSERT IGNORE INTO schema_migrations (version) VALUES ('004_large_jobs_dispatch');