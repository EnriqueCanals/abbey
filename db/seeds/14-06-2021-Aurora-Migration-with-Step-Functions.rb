body = <<~MARKDOWN
  #__June 14, 2021__

  **_How we migrated a multi-terabyte production MySQL database to Aurora MySQL, and built a Step Functions + Lambda pipeline to rebuild our lower environments on demand._**

  We finished migrating our primary production database from RDS MySQL to Aurora MySQL last month. The cutover was about 90 seconds of API maintenance, no data loss, and a measurable improvement in tail latency on the next business day. This is the writeup, including the part that turned out to be more valuable than the migration itself: a Step Functions pipeline that lets any engineer rebuild a fresh lower-environment database from a sanitized production snapshot in about 25 minutes.

  ## Why Aurora

  The case for Aurora over stock RDS MySQL, in our context:

  * **Storage decouples from compute.** Aurora's 6-way replicated storage layer means we stop worrying about EBS volume sizes, IOPS provisioning, and storage autoscaling as separate problems. Storage grows in 10GB increments automatically up to 128TB. We were spending real operational time on volume sizing in the legacy setup.
  * **Replica lag.** Our read replicas on classic RDS were chronically 200-800ms behind primary, occasionally spiking into multi-second territory during big writes. Aurora's storage-level replication eliminates the binlog-replay path, and our replica lag is consistently under 20ms.
  * **Backups and clones.** Aurora's clone-from-storage is the killer feature. A clone is effectively free on creation (copy-on-write at the storage layer) and is available in single-digit minutes regardless of database size. This is the foundation of the lower-environment rebuild pipeline.
  * **Failover.** Aurora's failover is typically under 30 seconds. Classic RDS Multi-AZ was taking us 90-120 seconds in the failovers we had triggered, and during a real incident every one of those seconds is excruciating.

  The case against, in our context: cost. Aurora is more expensive per instance-hour than the equivalent RDS MySQL instance. We modeled the total cost (instances + storage + IOPS + backup storage) and the difference, factoring in the storage cost we no longer had to over-provision, was a low-single-digit-percent increase. Worth it for the operational properties.

  ## The migration plan

  The constraint was that the storefront could not be down for more than a couple of minutes during business hours, and we were not willing to do a multi-hour weekend cutover because some of our highest-traffic windows are weekends.

  The plan:

  1. **Take a snapshot of the production RDS MySQL instance.** Restore it as a new Aurora MySQL cluster. This becomes our migration target.
  2. **Start AWS DMS** (Database Migration Service) replicating from the source RDS instance to the Aurora target, with the snapshot as the starting point and binlog replication catching up the delta.
  3. **Let DMS run for a couple of days.** Validate that the row counts match, that the schema migrations applied during this window made it through, and that DMS is not falling behind.
  4. **Cutover window.** Stop writes to the source (we did this by flipping a feature flag that put the API into read-only mode), wait for DMS to drain (about 8 seconds in our case), point the app at the Aurora endpoint via a CNAME update, validate, and re-enable writes.
  5. **Keep the source running, read-only, for a week.** As a fallback. We never used it. We could have.

  Total cutover window from "API goes read-only" to "API back to read-write on Aurora" was 88 seconds. Most of that was DNS propagation; the actual database swap was about 12 seconds.

  ## The DMS gotchas

  DMS has a long list of gotchas. The ones that bit us:

  **Foreign keys are not migrated by default.** DMS in "full load" mode disables foreign key constraints on the target during the bulk copy, which is correct (otherwise insertion order matters). It then re-enables them at the end. If your schema has any FK that the source has been violating (because of a long-ago bug, a manual data fix, whatever), DMS's re-enable step fails and leaves you with no FKs. We found three such violations on our staging migration and cleaned them up before doing it on production.

  **Time zones.** Aurora MySQL's default `time_zone` is UTC. Our RDS MySQL had been set to `US/Pacific` years ago by someone who is no longer at the company. Several application code paths assumed the database was in Pacific. We didn't catch this until staging and had to add explicit `CONVERT_TZ` calls in a handful of queries. Lesson: make `SELECT @@global.time_zone` part of your migration validation checklist.

  **Triggers.** DMS does not migrate triggers. You have to re-create them on the target after the bulk load. We had four legacy triggers (one of which I am pretty sure nobody had remembered existed) and the migration would have silently broken without manual re-creation.

  **Maximum LOB size.** DMS has a setting for max LOB size that defaults to 32KB. Our `product_descriptions.body` field is a `TEXT` column that, for a small number of products, exceeds that. The default truncates silently. We bumped it to 4MB and validated row-by-row on the impacted tables before cutover.

  ## The lower-environment rebuild pipeline

  Here is the part I want to spend more time on because I think it is the more interesting outcome.

  Before the migration, rebuilding a developer's local database or refreshing the staging database from production was a multi-hour, mostly-manual process. Someone would take a snapshot, restore it, run a sanitization script that scrubbed PII, generate a dump, copy the dump around, restore it. It happened maybe once a month and required someone with elevated AWS permissions.

  After the migration we built a Step Functions state machine that does the entire thing on demand:

  ```json
  {
    "Comment": "Rebuild a sanitized lower environment from production",
    "StartAt": "CloneProduction",
    "States": {
      "CloneProduction": {
        "Type": "Task",
        "Resource": "arn:aws:lambda:us-east-1:000000000000:function:db-clone",
        "Next": "WaitForCloneAvailable"
      },
      "WaitForCloneAvailable": {
        "Type": "Task",
        "Resource": "arn:aws:states:::aws-sdk:rds:waitForResource",
        "Parameters": {
          "ResourceType": "dbCluster",
          "Identifier.$": "$.cloneClusterId",
          "WaitFor": "available"
        },
        "Next": "Sanitize"
      },
      "Sanitize": {
        "Type": "Task",
        "Resource": "arn:aws:lambda:us-east-1:000000000000:function:db-sanitize",
        "Parameters": {
          "clusterId.$": "$.cloneClusterId",
          "environment.$": "$.targetEnvironment"
        },
        "Next": "Snapshot"
      },
      "Snapshot": {
        "Type": "Task",
        "Resource": "arn:aws:lambda:us-east-1:000000000000:function:db-snapshot",
        "Parameters": {
          "clusterId.$": "$.cloneClusterId",
          "snapshotName.$": "$.snapshotName"
        },
        "Next": "RestoreToTarget"
      },
      "RestoreToTarget": {
        "Type": "Task",
        "Resource": "arn:aws:lambda:us-east-1:000000000000:function:db-restore-to-env",
        "Parameters": {
          "snapshotName.$": "$.snapshotName",
          "environment.$": "$.targetEnvironment"
        },
        "Next": "TeardownClone"
      },
      "TeardownClone": {
        "Type": "Task",
        "Resource": "arn:aws:lambda:us-east-1:000000000000:function:db-teardown",
        "Parameters": {
          "clusterId.$": "$.cloneClusterId"
        },
        "End": true
      }
    }
  }
  ```

  Each Lambda is short, single-purpose, and idempotent. The state machine is invoked from a tiny internal CLI (`stack db rebuild --env=qa`) that an engineer can run from their laptop. Permission checks happen in the CLI's IAM role assumption step; the Lambdas run with the minimum permissions they need.

  The five steps, in plain English:

  1. **CloneProduction**: Use the Aurora clone-from-storage API to create a new cluster from the current production data. Takes about 90 seconds to provision. This is the magic step — clones share storage with the source until a page is written, which means we are not actually copying any data.
  2. **Sanitize**: Run a series of UPDATE statements against the clone that scrub PII. Emails get rewritten to `user_$id@example.invalid`, names get replaced with faker output, payment method tokens get wiped, password hashes get re-set to a known test value. The list is in a YAML file that the privacy team owns and reviews quarterly.
  3. **Snapshot**: Take a manual snapshot of the sanitized clone. This is the artifact we restore from.
  4. **RestoreToTarget**: Replace the target environment's database with a restore from the sanitized snapshot. The CNAME for that environment's database endpoint gets updated, and the old cluster gets terminated after a brief overlap window.
  5. **TeardownClone**: Delete the clone cluster. The snapshot persists.

  End to end, about 25 minutes for our database size. Cost per run is in single-digit dollars.

  ## What this changes

  Before this pipeline, the staging database was perpetually drifting from production because nobody wanted to spend a day refreshing it. Bugs that reproduced in staging often did not reproduce in production and vice versa. Developers worked against a six-month-old snapshot of the data and got surprised by edge cases that production had been quietly handling for months.

  After this pipeline, staging is rebuilt every weekday morning by a scheduled invocation of the state machine. Any engineer can rebuild their own personal environment in under half an hour. The drift between environments has effectively gone to zero, and the number of "but it works on staging" tickets has dropped to single digits per month.

  The migration itself was a one-time piece of value. The pipeline is a piece of infrastructure that pays out forever. If I were doing this again, I would have built the pipeline before the migration and used it to validate the cutover plan ten times over before pulling the trigger.

  ## Postmortem-style notes

  Things that went well:

  * The DMS-based replication strategy meant the cutover window was small enough that we could do it during normal business hours. Anything multi-hour would have been on a weekend, which would have meant fewer eyes on it, which would have meant a worse outcome if something went wrong.
  * The week-long parallel-running window after cutover was a comfort blanket that we did not use, but having it meant several skeptical stakeholders were comfortable signing off on a weekday cutover.
  * The Lambdas in the rebuild pipeline are unit-tested with `moto` mocks, which caught at least three IAM-permission bugs before they hit production.

  Things I would change:

  * I would have started running DMS three weeks before cutover, not one. The extra time would have caught the foreign-key issue and one of the time-zone issues earlier, and we could have done two practice cutovers in staging instead of one.
  * The CLI for invoking the pipeline grew organically and is now a small mess. It should have been a proper internal tool from day one, with audit logging and approval gates for production-impacting operations. We are rebuilding it.

  Next post will be on the WAF and bot-mitigation work, which is the other infrastructure project that ate a big chunk of this year. Stay tuned.
MARKDOWN

begin
  Post.create!(
    title: "Migrating to Aurora MySQL and Rebuilding Environments with Step Functions",
    created_at: "June 14, 2021",
    markdown_body: body,
    markdown_excerpt: "How we migrated a multi-terabyte production MySQL database to Aurora MySQL, and built a Step Functions + Lambda pipeline to rebuild our lower environments on demand.",
    post_tags: "aws,aurora,mysql,step-functions,lambda,dms,database,migration"
  )
  puts "Imported Migrating to Aurora MySQL and Rebuilding Environments with Step Functions"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 14-06-2021-Aurora-Migration-with-Step-Functions: #{e.message}"
rescue => e
  puts "Unexpected error importing 14-06-2021-Aurora-Migration-with-Step-Functions: #{e.message}"
end
