ALTER TABLE "transactions" ADD COLUMN "type_confidence" numeric(3, 2);--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "type_source" text;