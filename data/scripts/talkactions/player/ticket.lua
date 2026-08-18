local ticketTalkAction = TalkAction("!ticket", "!support")

local TICKET_CATEGORIES = {
	{ id = "general", name = "General Support / Question" },
	{ id = "bug", name = "Bug Report" },
	{ id = "rule_violation", name = "Player Report / Rule Violation" },
	{ id = "account_store", name = "Account & Store / Donation Issue" },
	{ id = "quest_npc", name = "Quest / NPC Issue" },
}

local function sendTicketDetailsModal(player, ticketId)
	local resultId = db.storeQuery(string.format("SELECT * FROM `server_tickets` WHERE `id` = %d AND `account_id` = %d", ticketId, player:getAccountId()))
	if not resultId then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Ticket not found.")
		return
	end

	local id = Result.getNumber(resultId, "id")
	local subject = Result.getString(resultId, "subject")
	local message = Result.getString(resultId, "message")
	local status = Result.getString(resultId, "status")
	local category = Result.getString(resultId, "category")
	local staffName = Result.getString(resultId, "staff_name")
	local createdAt = Result.getNumber(resultId, "created_at")
	local hasUnread = Result.getNumber(resultId, "has_unread_staff_reply")
	Result.free(resultId)

	-- Mark as read if opened
	if hasUnread == 1 then
		db.asyncQuery(string.format("UPDATE `server_tickets` SET `has_unread_staff_reply` = 0 WHERE `id` = %d", id))
	end

	-- Fetch replies
	local repliesText = ""
	local repliesResult = db.storeQuery(string.format("SELECT `author_type`, `author_name`, `message`, `created_at` FROM `server_ticket_replies` WHERE `ticket_id` = %d ORDER BY `id` ASC", id))
	if repliesResult then
		repeat
			local authorType = Result.getString(repliesResult, "author_type")
			local authorName = Result.getString(repliesResult, "author_name")
			local replyMsg = Result.getString(repliesResult, "message")
			local replyDate = os.date("%d/%m/%Y %H:%M", Result.getNumber(repliesResult, "created_at"))

			local roleTag = (authorType == "staff") and "[STAFF]" or "[YOU]"
			repliesText = repliesText .. string.format("\n--- %s %s (%s) ---\n%s\n", roleTag, authorName, replyDate, replyMsg)
		until not Result.next(repliesResult)
		Result.free(repliesResult)
	end

	local modalMsg = string.format(
		"Ticket #%d: %s\nStatus: %s | Category: %s\nCreated at: %s\nAssigned Staff: %s\n\n[Original Message]:\n%s\n%s",
		id,
		subject,
		status:upper(),
		category,
		os.date("%d/%m/%Y %H:%M", createdAt),
		staffName ~= "" and staffName or "None",
		message,
		repliesText ~= "" and ("\n[Conversation History]:" .. repliesText) or "\n(No replies yet from staff)"
	)

	player:showTextDialog(2597, modalMsg)
end

local function sendTicketListModal(player, showClosed)
	local accountId = player:getAccountId()
	local condition = showClosed and "`status` IN ('resolved', 'closed', 'rejected')" or "`status` IN ('open', 'in_progress')"
	local query = string.format("SELECT `id`, `subject`, `status`, `category`, `has_unread_staff_reply`, `created_at` FROM `server_tickets` WHERE `account_id` = %d AND %s ORDER BY `id` DESC LIMIT 25", accountId, condition)
	local resultId = db.storeQuery(query)

	if not resultId then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, showClosed and "You have no resolved/closed tickets." or "You have no active support tickets.")
		return
	end

	local window = ModalWindow({
		title = showClosed and "Closed Tickets" or "Active Support Tickets",
		message = "Select a ticket to view details and staff replies:",
	})

	repeat
		local id = Result.getNumber(resultId, "id")
		local subject = Result.getString(resultId, "subject")
		local status = Result.getString(resultId, "status")
		local hasUnread = Result.getNumber(resultId, "has_unread_staff_reply")

		local tag = (hasUnread == 1) and "[NEW REPLY] " or ""
		local choiceLabel = string.format("%s#%d [%s] %s", tag, id, status:upper(), subject:sub(1, 30))

		window:addChoice(choiceLabel, function(targetPlayer, button, choice)
			if button.name == "View" or button.name == "Select" then
				sendTicketDetailsModal(targetPlayer, id)
			end
		end)
	until not Result.next(resultId)
	Result.free(resultId)

	window:addButton("View")
	window:addButton("Back", function(targetPlayer)
		ticketTalkAction.onSay(targetPlayer, "!ticket", "")
	end)
	window:addButton("Close")
	window:setDefaultEnterButton(0)
	window:setDefaultEscapeButton(2)
	window:sendToPlayer(player)
end

local function sendNewTicketCategoryModal(player)
	local window = ModalWindow({
		title = "New Support Ticket",
		message = "Choose the category that best describes your request:\n(You can also use: !ticket create <category> <message>)",
	})

	for _, cat in ipairs(TICKET_CATEGORIES) do
		window:addChoice(cat.name, function(targetPlayer, button, choice)
			if button.name == "Select" then
				targetPlayer:sendTextMessage(
					MESSAGE_EVENT_ADVANCE,
					string.format("To submit your ticket in [%s], type:\n!ticket create %s <your message here>", cat.name, cat.id)
				)
			end
		end)
	end

	window:addButton("Select")
	window:addButton("Back", function(targetPlayer)
		ticketTalkAction.onSay(targetPlayer, "!ticket", "")
	end)
	window:addButton("Close")
	window:setDefaultEnterButton(0)
	window:setDefaultEscapeButton(2)
	window:sendToPlayer(player)
end

function ticketTalkAction.onSay(player, words, param)
	local split = param:splitTrimmed(" ")
	local subcmd = (split[1] or ""):lower()

	if subcmd == "create" or subcmd == "new" or subcmd == "add" then
		if #split < 3 then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Usage: !ticket create <category> <message>\nCategories: general, bug, rule_violation, account_store, quest_npc")
			return true
		end

		local category = split[2]:lower()
		local validCategory = false
		for _, cat in ipairs(TICKET_CATEGORIES) do
			if cat.id == category then
				validCategory = true
				break
			end
		end

		if not validCategory then
			category = "general"
		end

		local messageParts = {}
		for i = 3, #split do
			table.insert(messageParts, split[i])
		end
		local message = table.concat(messageParts, " ")

		if #message < 5 then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your ticket message is too short. Please provide more details.")
			return true
		end

		local currentTime = os.time()
		local accountId = player:getAccountId()
		local playerId = player:getGuid()
		local playerName = player:getName()
		local pos = player:getPosition()
		local subject = message:sub(1, 50)

		local query = string.format(
			"INSERT INTO `server_tickets` (`account_id`, `player_id`, `player_name`, `origin`, `category`, `subject`, `message`, `pos_x`, `pos_y`, `pos_z`, `status`, `priority`, `created_at`, `updated_at`) VALUES (%d, %d, %s, 'ingame_modal', %s, %s, %s, %d, %d, %d, 'open', 'medium', %d, %d)",
			accountId,
			playerId,
			db.escapeString(playerName),
			db.escapeString(category),
			db.escapeString(subject),
			db.escapeString(message),
			pos.x,
			pos.y,
			pos.z,
			currentTime,
			currentTime
		)

		db.asyncQuery(query)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your support ticket has been created successfully! The staff will review it shortly. Use !ticket to view status.")
		return true
	elseif subcmd == "view" then
		local ticketId = tonumber(split[2])
		if not ticketId then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Usage: !ticket view <ticket_id>")
			return true
		end
		sendTicketDetailsModal(player, ticketId)
		return true
	elseif subcmd == "list" then
		sendTicketListModal(player, false)
		return true
	elseif subcmd == "help" then
		local helpText = "Support Ticket System Commands:\n" ..
			"!ticket -> Open interactive support menu\n" ..
			"!ticket list -> View your active tickets\n" ..
			"!ticket view <id> -> View ticket details & replies\n" ..
			"!ticket create <category> <message> -> Create new ticket\n\n" ..
			"Categories: general, bug, rule_violation, account_store, quest_npc"
		player:showTextDialog(2597, helpText)
		return true
	end

	-- Main interactive modal menu
	local window = ModalWindow({
		title = "Support Helpdesk",
		message = string.format("Welcome to %s Support Desk!\nChoose an option below:", configManager.getString(configKeys.SERVER_NAME)),
	})

	window:addChoice("1. Create New Support Ticket", function(targetPlayer, button, choice)
		if button.name == "Select" then
			sendNewTicketCategoryModal(targetPlayer)
		end
	end)

	window:addChoice("2. View My Active Tickets", function(targetPlayer, button, choice)
		if button.name == "Select" then
			sendTicketListModal(targetPlayer, false)
		end
	end)

	window:addChoice("3. View Closed / Resolved Tickets", function(targetPlayer, button, choice)
		if button.name == "Select" then
			sendTicketListModal(targetPlayer, true)
		end
	end)

	window:addButton("Select")
	window:addButton("Close")
	window:setDefaultEnterButton(0)
	window:setDefaultEscapeButton(1)
	window:sendToPlayer(player)
	return true
end

ticketTalkAction:separator(" ")
ticketTalkAction:groupType("normal")
ticketTalkAction:register()
