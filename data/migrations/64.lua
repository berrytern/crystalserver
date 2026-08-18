function onUpdateDatabase()
	logger.info("Updating database to version 64 (feat: support tickets and reports system)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `server_tickets` (
			`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
			`account_id` INT UNSIGNED NOT NULL,
			`player_id` INT UNSIGNED NOT NULL,
			`player_name` VARCHAR(255) NOT NULL,
			`origin` ENUM('ingame_bug', 'ingame_rule_violation', 'ingame_modal', 'website') NOT NULL DEFAULT 'ingame_modal',
			`category` VARCHAR(50) NOT NULL DEFAULT 'general',
			`subject` VARCHAR(150) NOT NULL,
			`message` TEXT NOT NULL,
			`target_name` VARCHAR(255) NOT NULL DEFAULT '',
			`pos_x` INT NOT NULL DEFAULT 0,
			`pos_y` INT NOT NULL DEFAULT 0,
			`pos_z` INT NOT NULL DEFAULT 0,
			`status` ENUM('open', 'in_progress', 'resolved', 'closed', 'rejected') NOT NULL DEFAULT 'open',
			`priority` ENUM('low', 'medium', 'high', 'urgent') NOT NULL DEFAULT 'medium',
			`staff_id` INT UNSIGNED NULL DEFAULT NULL,
			`staff_name` VARCHAR(255) NOT NULL DEFAULT '',
			`has_unread_staff_reply` TINYINT(1) NOT NULL DEFAULT 0,
			`created_at` INT UNSIGNED NOT NULL,
			`updated_at` INT UNSIGNED NOT NULL,
			`closed_at` INT UNSIGNED NULL DEFAULT NULL,
			PRIMARY KEY (`id`),
			INDEX `idx_st_account` (`account_id`),
			INDEX `idx_st_player` (`player_id`),
			INDEX `idx_st_status` (`status`),
			INDEX `idx_st_origin` (`origin`),
			INDEX `idx_st_created` (`created_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
	]]) then
		logger.error("Failed to create table server_tickets.")
	end

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `server_ticket_replies` (
			`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
			`ticket_id` INT UNSIGNED NOT NULL,
			`author_type` ENUM('player', 'staff') NOT NULL,
			`author_id` INT UNSIGNED NOT NULL,
			`author_name` VARCHAR(255) NOT NULL,
			`message` TEXT NOT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			INDEX `idx_str_ticket` (`ticket_id`),
			CONSTRAINT `fk_server_ticket_replies_ticket`
				FOREIGN KEY (`ticket_id`) REFERENCES `server_tickets`(`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
	]]) then
		logger.error("Failed to create table server_ticket_replies.")
	end
end
