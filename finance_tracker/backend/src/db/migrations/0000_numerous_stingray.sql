CREATE TABLE "users" (
	"id" serial PRIMARY KEY NOT NULL,
	"email" text NOT NULL,
	"password_hash" text NOT NULL,
	"name" text NOT NULL,
	"currency" char(3) DEFAULT 'PKR' NOT NULL,
	"timezone" text DEFAULT 'Asia/Karachi' NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "refresh_tokens" (
	"id" serial PRIMARY KEY NOT NULL,
	"user_id" integer NOT NULL,
	"token_hash" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"revoked_at" timestamp with time zone,
	"ip_address" text,
	"user_agent" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "refresh_tokens_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
CREATE TABLE "sources" (
	"id" serial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "sources_name_unique" UNIQUE("name")
);
--> statement-breakpoint
CREATE TABLE "categories" (
	"id" serial PRIMARY KEY NOT NULL,
	"user_id" integer,
	"name" text NOT NULL,
	"icon" text DEFAULT '??' NOT NULL,
	"color" text DEFAULT '#BDC3C7' NOT NULL,
	"transaction_type" text DEFAULT 'expense' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "receipts" (
	"id" serial PRIMARY KEY NOT NULL,
	"user_id" integer NOT NULL,
	"transaction_id" integer,
	"input_type" text NOT NULL,
	"file_path" text,
	"file_hash" text,
	"original_file_name" text,
	"mime_type" text,
	"file_size_bytes" bigint,
	"raw_text" text,
	"raw_payload" jsonb,
	"ai_response" jsonb,
	"ai_model" text,
	"ocr_provider" text,
	"status" text DEFAULT 'queued' NOT NULL,
	"error_message" text,
	"attempts" integer DEFAULT 0 NOT NULL,
	"max_attempts" integer DEFAULT 3 NOT NULL,
	"locked_at" timestamp with time zone,
	"locked_by" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"processed_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "transactions" (
	"id" serial PRIMARY KEY NOT NULL,
	"user_id" integer NOT NULL,
	"source_id" integer NOT NULL,
	"category_id" integer,
	"receipt_id" integer,
	"amount" numeric(14, 2) NOT NULL,
	"currency" char(3) DEFAULT 'PKR' NOT NULL,
	"type" text DEFAULT 'expense' NOT NULL,
	"status" text DEFAULT 'confirmed' NOT NULL,
	"merchant" text,
	"description" text,
	"occurred_at" timestamp with time zone DEFAULT now() NOT NULL,
	"transaction_date" date NOT NULL,
	"card_last4" char(4),
	"bank_reference" text,
	"idempotency_key" text,
	"duplicate_of_transaction_id" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "budgets" (
	"id" serial PRIMARY KEY NOT NULL,
	"user_id" integer NOT NULL,
	"category_id" integer,
	"amount" numeric(14, 2) NOT NULL,
	"period" text DEFAULT 'monthly' NOT NULL,
	"month" char(7) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "categories" ADD CONSTRAINT "categories_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "receipts" ADD CONSTRAINT "receipts_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_source_id_sources_id_fk" FOREIGN KEY ("source_id") REFERENCES "public"."sources"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_receipt_id_receipts_id_fk" FOREIGN KEY ("receipt_id") REFERENCES "public"."receipts"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_refresh_tokens_user_id" ON "refresh_tokens" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_refresh_tokens_expires_at" ON "refresh_tokens" USING btree ("expires_at");--> statement-breakpoint
CREATE INDEX "idx_categories_user_id" ON "categories" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_receipts_user_id" ON "receipts" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_receipts_status" ON "receipts" USING btree ("status");--> statement-breakpoint
CREATE INDEX "idx_receipts_file_hash" ON "receipts" USING btree ("user_id","file_hash");--> statement-breakpoint
CREATE INDEX "idx_transactions_user_date" ON "transactions" USING btree ("user_id","transaction_date");--> statement-breakpoint
CREATE INDEX "idx_transactions_user_occurred" ON "transactions" USING btree ("user_id","occurred_at");--> statement-breakpoint
CREATE INDEX "idx_transactions_user_status" ON "transactions" USING btree ("user_id","status");--> statement-breakpoint
CREATE INDEX "idx_transactions_user_source" ON "transactions" USING btree ("user_id","source_id");--> statement-breakpoint
CREATE INDEX "idx_transactions_user_category" ON "transactions" USING btree ("user_id","category_id");--> statement-breakpoint
CREATE INDEX "idx_transactions_user_type" ON "transactions" USING btree ("user_id","type");--> statement-breakpoint
CREATE INDEX "idx_transactions_idempotency" ON "transactions" USING btree ("user_id","idempotency_key");--> statement-breakpoint
CREATE INDEX "idx_budgets_user_month" ON "budgets" USING btree ("user_id","month");--> statement-breakpoint
CREATE INDEX "idx_budgets_user_category_month" ON "budgets" USING btree ("user_id","category_id","month");