if SAM_LOADED then return end

local sam, command, language = sam, sam.command, sam.language

command.set_category("Fun")

do
	// Дефолтные значения. Прост чтоб было.
	local jailroom_pos = {
		Vector(-3896.862305, 3194.524902, 528.031250),
	}
	
	local unjailroom = function(ply)
		if not IsValid(ply) then return end
		if not ply:sam_get_nwvar("jailroom") then return end

		ply:sam_set_nwvar("jailroom", nil)
		ply:sam_set_nwvar("jailed_by", nil)
		ply:sam_set_nwvar("jailed_reason", nil)
		ply:sam_set_nwvar("jailed_time", nil)
		ply:sam_set_exclusive(nil)

		ply:SetViewOffset(Vector(0, 0, 64))
		ply:SetViewOffsetDucked(Vector(0, 0, 28))

		ply:Spawn()

		timer.Remove("SAM.Unjailroom." .. ply:SteamID())
		timer.Remove("SAM.Jailroom.Watch." .. ply:SteamID())
	end

	local jailroom = function(ply, time, banned_by, reason)
		if not IsValid(ply) then return end
		if not isnumber(time) or time < 0 then
			time = 0
		end

		if ply:sam_get_nwvar("frozen") then
			RunConsoleCommand("sam", "unfreeze", "#" .. ply:EntIndex())
		end

		if not ply:sam_get_nwvar("jailroom") then
			ply:ExitVehicle()
			ply:SetMoveType(MOVETYPE_WALK)
			ply:SetPos(jailroom_pos[math.random(#jailroom_pos)] or Vector(0,0,0))


			if ply:Team() ~= GAMEMODE.DefaultTeam then
				ply:changeTeam(GAMEMODE.DefaultTeam, true, true)
			end
			ply:sam_set_nwvar("jailroom", true)
			ply:sam_set_nwvar("jailed_by", ply:Nick())
			ply:sam_set_nwvar("jailed_reason", reason)
			ply:sam_set_nwvar("jailed_time", CurTime() + time)
			ply:sam_set_exclusive("in jailroom")

			ply:SetModelScale(0.2)
			ply:SetViewOffset(Vector(0, 0, 64 * 0.2))
			ply:SetViewOffsetDucked(Vector(0, 0, 28 * 0.2))
			ply:StripWeapons()
		end

		local steamid = ply:SteamID()

		if time == 0 then
			timer.Remove("SAM.Unjailroom." .. steamid)
		else
			timer.Create("SAM.Unjailroom." .. steamid, time, 1, function()
				if IsValid(ply) then
					unjailroom(ply)
				end
			end)
		end

		timer.Create("SAM.Jailroom.Watch." .. steamid, 0.5, 0, function()
			if not IsValid(ply) then
				return timer.Remove("SAM.Jailroom.Watch." .. steamid)
			end

			if ply:GetPos():DistToSqr(jailroom_pos[1]) > 1048576 then
				ply:SetPos(jailroom_pos[math.random(#jailroom_pos)])
			end
		end)
	end

	command.new("jailroom")
		:SetPermission("jailroom", "admin")

		:AddArg("player")
		:AddArg("length", {optional = true, default = 0, min = 0})
		:AddArg("text", {hint = "reason", optional = true, default = sam.language.get("default_reason")})

		:GetRestArgs()

		:Help(language.get("jail_help"))

		:OnExecute(function(ply, targets, length, reason)
			for i = 1, #targets do
				jailroom(targets[i], length * 60, ply, reason)
			end

			if sam.is_command_silent then return end
			sam.player.send_message(nil, "jail", {
				A = ply, T = targets, V = sam.format_length(length), V_2 = reason
			})
		end)
	:End()

	command.new("unjailroom")
		:SetPermission("unjailroom", "admin")

		:AddArg("player")

		:Help(language.get("unjail_help"))

		:OnExecute(function(ply, targets)
			for i = 1, #targets do
				unjailroom(targets[i])
			end

			if sam.is_command_silent then return end
			sam.player.send_message(nil, "unjail", {
				A = ply, T = targets
			})
		end)
	:End()


	if CLIENT then
		local ply, reason, time, banned_by
		local active_ban
		hook.Add("HUDPaint", "SAM.JailRoomPainting", function ()
			ply, reason, time, banned_by = LocalPlayer(), LocalPlayer():sam_get_nwvar("jailed_reason"), LocalPlayer():sam_get_nwvar("jailed_time"), LocalPlayer():sam_get_nwvar("jailed_by")
			active_ban = ply:sam_get_nwvar("jailroom")

			if active_ban then
				draw.SimpleTextOutlined("Вы в джайле!", "Trebuchet24", ScrW()/2, ScrH()/2, Color(255,255,255,255), 1, 1, 1, Color(0,0,0,255))
				draw.SimpleTextOutlined("Вас посадил : "..banned_by, "Trebuchet24", ScrW()/2, ScrH()/2 + 20, Color(255,255,255,255), 1, 1, 1, Color(0,0,0,255))
				draw.SimpleTextOutlined("По причине : "..reason, "Trebuchet24", ScrW()/2, ScrH()/2 + 40, Color(255,255,255,255), 1, 1, 1, Color(0,0,0,255))
				draw.SimpleTextOutlined("Осталось : "..string.FormattedTime(time - CurTime(), "%02i:%02i" ) , "Trebuchet24", ScrW()/2, ScrH()/2 + 60, Color(255,255,255,255), 1, 1, 1, Color(0,0,0,255))
			end
		end)


	end


	if SERVER then

		function InsertInDataBase(ply, time, reason, banned_by)
			if ply and time then
				time = time or 100
				reason = reason or "Unknow"
				banned_by = banned_by or "Unknow"
				local q = sql.Query("INSERT INTO SAM_JailRoomCache( S64, time, banned_by, reason ) VALUES ( '"..ply:SteamID64().."', '"..time.."', '"..banned_by.."', '"..reason.."')")
			end
		end

		function CheckJailRoomDataBase(ply)
			local query = sql.Query("SELECT * FROM SAM_JailRoomCache WHERE S64 = '"..ply:SteamID64().."'")
			if query then
				print ("[SAM JailRoom Debug] Found active ban in DB. Restoring...")
				// Так нужно ибо не успевает подгружать игрока
				timer.Simple(2, function ()
					jailroom(ply, tonumber(query[1].time), query[1].banned_by, query[1].reason )
					DarkRP.notify(ply,1,4,"У  вас был активный бан. TAKE IT BACK!")
					sql.Query("DELETE FROM SAM_JailRoomCache WHERE S64 = '"..ply:SteamID64().."'")
				end)
			end
		end

		hook.Add('OnGamemodeLoaded', "SAMJailRoomDataBaseCache", function ()
			if not sql.TableExists("SAM_JailRoomCache") then
				sql.Query("CREATE TABLE SAM_JailRoomCache( S64, time INT, banned_by VARCHAR, reason VARCHAR)")
				print ("[SAM JailRoom] DB 'SAM_JailRoomCache' created")
			else
				print ("[SAM JailRoom] DB 'SAM_JailRoomCache' exist!")
			end



			// Лол, я мог бы вносить все в БД но мне так лень.
			if file.Exists("sam_jailroom_pos.txt", "DATA") then
				local read = file.Read("sam_jailroom_pos.txt", "DATA")
				jailroom_pos = util.JSONToTable(read)
				print ("[SAM JailRoom] File pos loaded")
			else
				for i=0, 10 do 
					print ('[SAM JailRoom] WARNING. SET YOUR JAILROOM POS BY TYPING sam_set_jail_pos INTO CLIENT CONSOLE!!!')
				end
			end
		end)


		hook.Add("PlayerSpawn", "SAM.Jailroom", function(ply)
			if ply:sam_get_nwvar("jailroom") then
				ply:SetPos(jailroom_pos[math.random(#jailroom_pos)])
			end
		end)

		hook.Add("PlayerEnteredVehicle", "SAM.Jailroom", function(ply)
			if ply:sam_get_nwvar("jailroom") then
				ply:ExitVehicle()
			end
		end)

		// Добавил новый хук на чек при первом заходе.
		hook.Add("PlayerInitialSpawn", "SAM.JailRoomInitialSpawn", function (ply)
			print ("Checking player")
			CheckJailRoomDataBase(ply)
		end)


		local no_access = {
			"Effect",
			"NPC",
			"Object",
			"Prop",
			"Ragdoll",
			"SENT",
			"Vehicle"
		}


		hook.Add("PlayerSpawnSWEP", "WaifuChanLoveDick", function (ply)
			if ply:sam_get_nwvar("jailroom") then
				return false
			end
		end)


		for _, v in pairs (no_access) do
			hook.Add("PlayerSpawn"..v, "SAM.NoSpawnViaJailRoom"..v, function (ply)
				if ply:sam_get_nwvar("jailroom") then
					return false
				end
			end)
		end

		// Кусок который я изменяю.
		hook.Add("PlayerDisconnected", "SAM.Jailroom", function(ply)
			if ply:sam_get_nwvar("jailroom") then
				InsertInDataBase(ply, math.Round(timer.TimeLeft("SAM.Unjailroom."..ply:SteamID())), ply:sam_get_nwvar("jailed_reason"), ply:sam_get_nwvar("jailed_by"))
				print ("[SAM JailRoom Debug] "..ply:Nick().." leave server with active jail room ban. Inserting to database.")
				timer.Remove("SAM.Unjailroom." .. ply:SteamID())
				timer.Remove("SAM.Jailroom.Watch." .. ply:SteamID())
			end
		end)

		hook.Add("SAM.CanRunCommand", "SAM.PreventUsingCommandInJailRoom", function (ply, cmd, arg, cmd)
			if not sam.isconsole(ply) and ply:sam_get_nwvar("jailroom") then
				DarkRP.notify(ply,1, 4, "Вы не можете использовать админ команды пока вы находитесь в джайле.")
				return false
			end
		end)

		hook.Add("PlayerNoClip", "SAM.StopUsingNoclipViaBan", function (ply)
			if ply:sam_get_nwvar("jailroom") then
				DarkRP.notify(ply,1,4,"Вы не можете использовать ноуклип пока вы в бане!")
				return false
			end
		end)

		hook.Add("PlayerSay", "SAM.StopChatIfYouJailed", function (ply, str)
			if ply:sam_get_nwvar("jailroom") then
				return ""
			end
		end)

		hook.Add("PlayerCanHearPlayersVoice", "SAM.StopVoiceChatIfYouJailed", function (listener, talker)
			if talker:sam_get_nwvar("jailroom") then
				return false
			end
		end)

		hook.Add("CanPlayerSuicide", "SAM.StopAbuseSuicide", function (ply)
			if ply:sam_get_nwvar("jailroom") then
				return false
			end
		end)

		hook.Add("CanTool", "SAM.StopAbuseSuicide", function (ply)
			if ply:sam_get_nwvar("jailroom") then
				return false
			end
		end)


		hook.Add("SAM.CanPlayerSpawn", "SAM.StopAbuseSuicide", function (ply)
			if ply:sam_get_nwvar("jailroom") then
				return false
			end
		end)

		hook.Add("canChangeJob", "SAM.StopChangeJob", function (ply)
			if ply:sam_get_nwvar("jailroom") then
				return false, "Вы не можете сменить работу будучи в бане"
			end
		end)

		// Ну блять добавлю еще один хук на смену тимы. А вдруг чо)0
		hook.Add("playerCanChangeTeam", "SAM.StopAbuseChangingTeamFucker!", function (ply, team, force)
			if ply:sam_get_nwvar("jailroom") then
				return false, "Вы не можете сменить работу будучи в бане"
			end
		end)



		concommand.Add("sam_set_jail_pos", function (ply, cmd, arg)
			if ply:IsSuperAdmin() then
				local new_pos = {Vector(ply:GetPos().x, ply:GetPos().y, ply:GetPos().z)}

				local into_json = util.TableToJSON(new_pos)
				file.Write("sam_jailroom_pos.txt", into_json)
				ply:ChatPrint("Координаты сохранены на сервере. ЭТО НУЖНО ДЕЛАТЬ ОДИН РАЗ.")
				ply:ChatPrint("КАЖДЫЙ НОВЫЙ РАЗ ЛИШЬ ПЕРЕЗАПИСЫВАЕТ ВАШИ ДАННЫЕ!")
			else
				ply:ChatPrint("У вас недостаточно прав или нет админки на сервере. ХЗ))0")
			end
		end)
	end
end
