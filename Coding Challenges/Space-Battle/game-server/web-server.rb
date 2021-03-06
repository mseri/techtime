
# encoding: UTF-8

# ------------------------------------------------------------
# utils

require 'sinatra'
# http://www.sinatrarb.com/intro.html

require 'securerandom'
# SecureRandom.hex    #=> "eb693ec8252cd630102fd0d0fb7c3485"
# SecureRandom.hex(2) #=> "eb69"
# SecureRandom.uuid   #=> "2d931510-d99f-494a-8c67-87feb05e1594"

require 'digest/sha1'
# Digest::SHA1.hexdigest 'foo'
# Digest::SHA1.file(myFile).hexdigest

require 'json'

require 'find'

require 'fileutils'
# FileUtils.mkpath '/a/b/c'
# FileUtils.cp(src, dst)
# FileUtils.mv 'oldname', 'newname'
# FileUtils.rm(path_to_image)
# FileUtils.rm_rf('dir/to/remove')

require 'time'

require 'digest/sha1'
# Digest::SHA1.hexdigest 'foo'
# Digest::SHA1.file(myFile).hexdigest

# --  --------------------------------------------------

require_relative "library/BombsUtils.rb"
require_relative "library/MapUtils.rb"
require_relative "library/Navigation.rb"
require_relative "library/ScoringUtils.rb"
require_relative "library/UserKeys.rb"
require_relative "library/UserFleet.rb"
require_relative "library/Throttling.rb"

require_relative "GameLibrary.rb"

# --  --------------------------------------------------

LUCILLE_INSTANCE = ENV["COMPUTERLUCILLENAME"]

if LUCILLE_INSTANCE.nil? then
    puts "Error: Environment variable 'COMPUTERLUCILLENAME' is not defined."
    exit
end

SERVER_FOLDERPATH = File.dirname(__FILE__)

GAME_INSTANCE_DATA_FOLDERPATH = "/Galaxy/DataBank/Space-Battle-Server/#{LUCILLE_INSTANCE}"
GAME_PARAMETERS_FILEPATH = File.dirname(__FILE__) + "/game-parameters.json"
$GAME_PARAMETERS = JSON.parse(IO.read(GAME_PARAMETERS_FILEPATH)) # This is the first load, the file is duplicated and (re)read when a new map is created

$usersFleetsIOActionsMutex = Mutex.new
$mapInitMutex = Mutex.new

SERVER_LAST_RESTART_DATETIME = Time.new.utc.iso8601

File.open("#{GAME_INSTANCE_DATA_FOLDERPATH}/server-last-restart-datetime.txt", "w"){|f| f.print(SERVER_LAST_RESTART_DATETIME) }

# -- --------------------------------------------------
# Route

=begin

    HTTP error codes:
        401 Unauthorized
        403 Forbidden
        404 Not Found

=end

set :port, 14561
#set :public_folder, "path/to/www"

not_found do
  '404'
end

get '/' do
    content_type 'text/plain'
    [
        "Space Battle. Game Server. Running at #{LUCILLE_INSTANCE}",
        "See https://github.com/guardian/techtime/tree/master/Coding%20Challenges/20180920-Weekly for details."
    ].join("\n") + "\n"
end

# ------------------------------------------
# Server

get '/server/last-restart-datetime' do
    content_type 'text/plain'
    SERVER_LAST_RESTART_DATETIME + "\n"
end

# ------------------------------------------
# Map and Game Parameters

get '/game/v1/map' do
    content_type 'application/json'
    JSON.generate(MapUtils::getCurrentMap())
end

get '/game/v1/parameters' do
    content_type 'application/json'
    JSON.pretty_generate($GAME_PARAMETERS)
end

# ------------------------------------------
# User Fleet Actions 

get '/game/v1/:userkey/:mapid/capital-ship/init' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if username.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    if UserFleet::getUserFleetDataOrNull(currentHour, username) then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "3b6f4992", "You cannot init a Capital Ship, you already have one for this hour"))
    end

    # ------------------------------------------------------

    mapPoint = MapUtils::getCurrentMap()["points"].sample
    capitalShipInitialEnergy = $GAME_PARAMETERS["fleetCapitalShipInitialEnergyLevel"]
    topUpChallengeDifficulty = $GAME_PARAMETERS["fleetCapitalShipTopUpChallengeDifficulty"]
    userFleet = UserFleet::spawnUserFleet(username, mapPoint, capitalShipInitialEnergy, topUpChallengeDifficulty)

    UserFleet::commitFleetToDisk(currentHour, username, userFleet)

    JSON.generate(GameLibrary::make200Answer(nil, currentHour, username))
end

get '/game/v1/:userkey/:mapid/fleet' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if username.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    if UserFleet::getUserFleetDataOrNull(currentHour, username).nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "95a0b4e5", "You do not yet have a fleet for this hour. (You should initiate one.)"))
    end

    JSON.generate(GameLibrary::make200Answer(nil, currentHour, username))
end

get '/game/v1/:userkey/:mapid/capital-ship/top-up/:code' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]
    code = params["code"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if username.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "95a0b4e5", "You do not yet have a fleet for this hour. (You should initiate one.)"))
    end

    if !userFleet["ships"][0]["alive"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "86877586", "Your capital ship for this hour is dead"))
    end

    # ------------------------------------------------------    

    if UserFleet::validateTopUpCode(currentHour, username, code) then
        if userFleet["ships"][0]["energyLevel"] + $GAME_PARAMETERS["fleetCapitalShipTopUpEnergyValue"] <= $GAME_PARAMETERS["fleetShipsMaxEnergy"]["capitalShip"] then
            topUpEnergyValue = $GAME_PARAMETERS["fleetCapitalShipTopUpEnergyValue"]
            difficulty = $GAME_PARAMETERS["fleetCapitalShipTopUpChallengeDifficulty"]
            UserFleet::topUpCapitalShipAndResetTopUpChallenge(currentHour, username, topUpEnergyValue, difficulty)
            JSON.generate(GameLibrary::make200Answer(nil, currentHour, username))
        else
            JSON.generate(GameLibrary::makeErrorAnswer(403, "d7713626", "Your code is correct, please keep it (!), but you cannot submit it at this time. Your ship has too much energy in reserve."))
        end
    else
        JSON.generate(GameLibrary::makeErrorAnswer(403, "d07feb9c", "Your code is not a solution to the challenge"))
    end
end

get '/game/v1/:userkey/:mapid/capital-ship/create-battle-cruiser' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if username.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "95a0b4e5", "You do not yet have a fleet for this hour. (You should initiate one.)"))
    end

    if !userFleet["ships"][0]["alive"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "86877586", "Your capital ship for this hour is dead"))
    end

    # ------------------------------------------------------

    battleCruiserBuildEnergyCost = $GAME_PARAMETERS["fleetBattleCruiserBuildEnergyCost"]
    battleCruiserInitialEnergyLevel = $GAME_PARAMETERS["fleetBattleCruiserInitialEnergyLevel"]

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)
    capitalShipCanPerformBattleShipCreation = userFleet["ships"][0]["energyLevel"] >= ( battleCruiserBuildEnergyCost + battleCruiserInitialEnergyLevel )
    if capitalShipCanPerformBattleShipCreation then
        userFleet["ships"][0]["energyLevel"] = userFleet["ships"][0]["energyLevel"] - ( battleCruiserBuildEnergyCost + battleCruiserInitialEnergyLevel )
        mapPoint = MapUtils::getCurrentMap()["points"].sample
        battleCruiser = UserFleet::spawnBattleCruiser(mapPoint, battleCruiserInitialEnergyLevel)
        userFleet["ships"] << battleCruiser
        UserFleet::commitFleetToDisk(currentHour, username, userFleet)
        JSON.generate(GameLibrary::make200Answer(battleCruiser, currentHour, username))
    else
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "36be6a8b", "Your capital ship doesn't have enough energy to complete the construction of a battle cruiser. You have #{userFleet["ships"][0]["energyLevel"]} but you need #{(battleCruiserBuildEnergyCost+battleCruiserInitialEnergyLevel)}"))
    end
end

get '/game/v1/:userkey/:mapid/capital-ship/create-energy-carrier/:energyamount' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]

    energyamount = params["energyamount"].to_f

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if username.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "95a0b4e5", "You do not yet have a fleet for this hour. (You should initiate one.)"))
    end

    if !userFleet["ships"][0]["alive"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "86877586", "Your capital ship for this hour is dead"))
    end

    if energyamount > $GAME_PARAMETERS["fleetShipsMaxEnergy"]["energyCarrier"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "b68c3046", "You are creating a carrier with too much energy. Upper limit is #{$GAME_PARAMETERS["fleetShipsMaxEnergy"]["energyCarrier"]} units of energy."))    
    end

    # ------------------------------------------------------ 

    carrierBuildEnergyCost = $GAME_PARAMETERS["fleetEnergyCarrierBuildEnergyCost"]
    carrierInitialEnergyLevel = energyamount 

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)
    capitalShipCanPerformCarrierCreation = userFleet["ships"][0]["energyLevel"] >= ( carrierBuildEnergyCost + carrierInitialEnergyLevel )
    if capitalShipCanPerformCarrierCreation then
        userFleet["ships"][0]["energyLevel"] = userFleet["ships"][0]["energyLevel"] - ( carrierBuildEnergyCost + carrierInitialEnergyLevel )
        mapPoint = MapUtils::getCurrentMap()["points"].sample
        energyCarrier = UserFleet::spawnEnergyCarrier(mapPoint, carrierInitialEnergyLevel)
        userFleet["ships"]<< energyCarrier
        UserFleet::commitFleetToDisk(currentHour, username, userFleet)
        JSON.generate(GameLibrary::make200Answer(energyCarrier, currentHour, username))
    else
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "fc31efd0", "Your capital ship doesn't have enough energy to complete the construction of an energy carrier carrying #{carrierInitialEnergyLevel}. You have #{userFleet["ships"][0]["energyLevel"]} but you need #{(carrierBuildEnergyCost+carrierInitialEnergyLevel)}"))
    end
end

get '/game/v1/:userkey/:mapid/jump/:shipuuid/:targetpointlabel' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]

    shipuuid = params["shipuuid"]
    targetPointLabel = params["targetpointlabel"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if username.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # Map Validation

    map = MapUtils::getCurrentMap()    

    targetMapPoint = MapUtils::getPointForlabelAtMapOrNull(targetPointLabel, map)
    if targetMapPoint.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "34d25d8a", "The specified point doesn't exist"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "95a0b4e5", "You do not yet have a fleet for this hour. (You should initiate one.)"))
    end

    # Need to check whether we own a ship of with that uuid, and retrieve it.
    ship = UserFleet::getShipPerUUIDOrNull(currentHour, username, shipuuid)
    if ship.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "acfec803", "Your fleet has no ship with this uuid"))
    end

    # Need to check whether the ship is alive ot not
    if !ship["alive"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "f7a8dee2", "The ship is dead"))
    end    

    # In the current version of the game energy carriers need the capital ship to be alive 
    # in order to be controlled. Therfore we record whether or not the capital is alive.

    if ship["nomenclature"] == "energyCarrier" then
        if !userFleet["ships"][0]["alive"] then
            return JSON.generate(GameLibrary::makeErrorAnswer(403, "03717296", "Your capital ship is dead. You cannot jump energy carriers in that case."))
        end 
    end

    sourceMapPoint = ship["location"]

    jec = Navigation::jumpEnergyCost(sourceMapPoint, targetMapPoint, ship["nomenclature"])

    # Need to check whether the ship has enough energy left to jump
    if ship["energyLevel"] < jec then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "c36b1859", "The ship doesn't have enough energy for this jump. Available: #{ship["energyLevel"]}. Required: #{jec}"))
    end    

    # ------------------------------------------------------
    
    # Now performing the jump
    ship["location"] = targetMapPoint
    ship["energyLevel"] = ship["energyLevel"] - jec

    userFleet = UserFleet::insertOrUpdateShipAtFleet(userFleet, ship)

    shipNomenclatureToPointIncrease = {
        "energyCarrier" => 1,
        "battleCruiser" => 10,
        "capitalShip"   => 50
    }

    if !userFleet["mapExploration"].include?(targetMapPoint["label"]) then
        userFleet["mapExploration"] << targetMapPoint["label"]
        userFleet["gameScore"] = userFleet["gameScore"] + shipNomenclatureToPointIncrease[ship["nomenclature"]]
    end

    UserFleet::commitFleetToDisk(currentHour, username, userFleet)

    JSON.generate(GameLibrary::make200Answer(nil, currentHour, username))
end

get '/game/v1/:userkey/:mapid/energy-transfer/:ship1uuid/:ship2uuid/:amount' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]

    ship1uuid = params["ship1uuid"]
    ship2uuid = params["ship2uuid"]
    amountToTransfer = params["amount"].to_f

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if username.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    if ship1uuid==ship2uuid then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "66474ae3", "You are transferring energy from a ship to itself."))
    end

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "95a0b4e5", "You do not yet have a fleet for this hour. (You should initiate one.)"))
    end

    ship1 = UserFleet::getShipPerUUIDOrNull(currentHour, username, ship1uuid)
    ship2 = UserFleet::getShipPerUUIDOrNull(currentHour, username, ship2uuid)

    if ship1.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "7b680a12", "Your fleet has no ship with uuid #{ship1uuid}"))
    end

    if ship2.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "1c5436b9", "Your fleet has no ship with uuid #{ship2uuid}"))
    end

    if !ship1["alive"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "391388ae", "The source ship, #{ship1uuid}, is dead"))
    end

    if !ship2["alive"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "a9e028ed", "The target ship, #{ship2uuid}, is dead"))
    end

    if ship2["location"]["label"] != ship1["location"]["label"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "a9971906", "You cannot transfer energy between the two ships, they are not at the same map location"))
    end

    if ship1["energyLevel"] == 0 then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "cf1e71c1", "The source ship has no energy to transfer"))
    end    

    amountToTransfer = [ amountToTransfer, $GAME_PARAMETERS["fleetShipsMaxEnergy"][ship2["nomenclature"]] - ship2["energyLevel"] ].min

    # ------------------------------------------------------

    ship2["energyLevel"] = ship2["energyLevel"] + amountToTransfer
    ship1["energyLevel"] = ship1["energyLevel"] - amountToTransfer

    userFleet = UserFleet::insertOrUpdateShipAtFleet(userFleet, ship1)
    userFleet = UserFleet::insertOrUpdateShipAtFleet(userFleet, ship2)
    UserFleet::commitFleetToDisk(currentHour, username, userFleet)

    JSON.generate(GameLibrary::make200Answer([ ship1, ship2 ], currentHour, username))
end

get '/game/v1/:userkey/:mapid/bomb/:battlecruisershipuuid/:targetpointlabel' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]

    attackerBattleCruiserShipUUID = params["battlecruisershipuuid"]
    targetpointlabel = params["targetpointlabel"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    attackerUsername = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if attackerUsername.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # Map Validation

    map = MapUtils::getCurrentMap()

    targetMapPoint = MapUtils::getPointForlabelAtMapOrNull(targetpointlabel, map)
    if targetMapPoint.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "88bb18fd", "The specified point doesn't exist"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    attackerUserFleet = UserFleet::getUserFleetDataOrNull(currentHour, attackerUsername)

    if attackerUserFleet.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "95a0b4e5", "You do not yet have a fleet for this hour. (You should initiate one.)"))
    end

    attackerBattleCruiser = UserFleet::getShipPerUUIDOrNull(currentHour, attackerUsername, attackerBattleCruiserShipUUID)

    if attackerBattleCruiser.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "1a0ddb98", "Your fleet has no ship with uuid #{attackerBattleCruiserShipUUID}"))
    end

    if !attackerBattleCruiser["alive"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "bc0bb00f", "Your attacking battle cruiser is dead"))
    end

    # ------------------------------------------------------
    # At this point we can attempt shooting

    if attackerBattleCruiser["energyLevel"] < ( $GAME_PARAMETERS["fleetBattleCruiserBombBuildingCost"] + $GAME_PARAMETERS["fleetBattleCruiserBombNominalEnergy"] ) then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "943802d8", "Your attacking battle cruiser doesn't have enough energy to complete the construction of a bomb"))   
    end

    attackerBattleCruiser["energyLevel"] = attackerBattleCruiser["energyLevel"] - ( $GAME_PARAMETERS["fleetBattleCruiserBombBuildingCost"] + $GAME_PARAMETERS["fleetBattleCruiserBombNominalEnergy"] )
    attackerUserFleet = UserFleet::insertOrUpdateShipAtFleet(attackerUserFleet, attackerBattleCruiser)
    UserFleet::commitFleetToDisk(currentHour, attackerUsername, attackerUserFleet)

    # Shooting happened from the point of view of the attacker (attacker user fleet is not yet to disk)

    # ------------------------------------------------------
    # Ok, now time to do damage

    distanceToTargetPoint = MapUtils::distanceBetweenTwoMapPoints(attackerBattleCruiser["location"], targetMapPoint)
    bombEffectiveEnergy = BombsUtils::bombEffectiveEnergy($GAME_PARAMETERS["fleetBattleCruiserBombNominalEnergy"], distanceToTargetPoint)

    attackerAllShipsDamageReport = []

    GameLibrary::userFleetsForHour(currentHour)
        .each{|targetPlayerXUserFleet|
            UserFleet::userShipsWithinDisk(currentHour, targetPlayerXUserFleet["username"], attackerBattleCruiser["location"], 0)
                .each{|targetShipX|
                    targetPlayerXUserFleet, targetShipX, damageCausedOnTargetShipXForAttackerPlayerReport = UserFleet::registerShipTakingBombImpact(targetPlayerXUserFleet, attackerBattleCruiser["location"], attackerUsername, targetShipX, bombEffectiveEnergy)
                    attackerAllShipsDamageReport << damageCausedOnTargetShipXForAttackerPlayerReport
                    targetPlayerXUserFleet = UserFleet::insertOrUpdateShipAtFleet(targetPlayerXUserFleet, targetShipX)
                }
            UserFleet::commitFleetToDisk(currentHour, targetPlayerXUserFleet["username"], targetPlayerXUserFleet)
            # Target players fleet have been updated. One clean call to UserFleet::commitFleetToDisk after having updated every ship at the bombing location   
        }


    # ------------------------------------------------------
    # Now we only need to compute any point increase for the attacker and commit the attacker fleet to disk

    # attackerAllShipsDamageReport contains either nil or this
    #{
    #    "username"     => userFleet["username"],
    #    "nomenclature" => targetShip["nomenclature"],
    #    "alive"        => targetShip["alive"]
    #}    

    attackerAllShipsDamageReport = attackerAllShipsDamageReport.compact # better    
    attackerAllShipsDamageReport
    .select{|item|
        !item["alive"]
    }
    .each{|item|
        GameLibrary::doUserFleetPointIncreaseForShipDestroyed(currentHour, attackerUsername, item["nomenclature"])
    }
    
    JSON.generate(GameLibrary::make200Answer(attackerAllShipsDamageReport, currentHour, attackerUsername))
end

get '/game/v1/:userkey/:mapid/space-probe/:battlecruisershipuuid' do

    content_type 'application/json'

    userkey = params["userkey"]
    mapId = params["mapid"]

    battleCruiserShipUUID = params["battlecruisershipuuid"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # Throttling

    Throttling::throttle(userkey)

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if username.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(401, "c26b7c33", "Invalid userkey"))
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "6cd08e91", "Map not found (mapId is incorrect or outdated)"))
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "95a0b4e5", "You do not yet have a fleet for this hour. (You should initiate one.)"))
    end

    battleCruiser = UserFleet::getShipPerUUIDOrNull(currentHour, username, battleCruiserShipUUID)

    if battleCruiser.nil? then
        return JSON.generate(GameLibrary::makeErrorAnswer(404, "a0ce7e39", "Your fleet has no ship with uuid #{battleCruiserShipUUID}"))
    end

    if !battleCruiser["alive"] then
        return JSON.generate(GameLibrary::makeErrorAnswer(403, "051366e2", "The probing battle cruiser is dead"))
    end

    # ------------------------------------------------------
    # At this point we can attempt shooting

    spaceProbeResults = {
        "unixtime" => Time.new.to_f,
        "datetime" => Time.now.utc.iso8601,
        "location" => battleCruiser["location"],
        "results"  => []
    }

    GameLibrary::userFleetsForHour(currentHour)
        .each{|otherPlayerUserFleet|
            next if otherPlayerUserFleet["username"] == username
            UserFleet::userShipsWithinDisk(currentHour, otherPlayerUserFleet["username"], battleCruiser["location"], 300)
                .each{|ship|
                    spaceProbeResultItem = {
                        "location" => ship["location"],
                        "nomenclature" => ship["nomenclature"],
                        "username" => otherPlayerUserFleet["username"]
                    }
                    spaceProbeResults["results"] << spaceProbeResultItem
                }
        }

    userFleet["spaceProbeResults"][battleCruiser["uuid"]] = spaceProbeResults

    UserFleet::commitFleetToDisk(currentHour, username, userFleet)

    JSON.generate(GameLibrary::make200Answer(spaceProbeResults, currentHour, username))
end

get '/game/v1/scores/?:hourcode1?/?:hourcode2?' do

    hourCode1 = params["hourcode1"]
    hourCode2 = params["hourcode2"]

    if hourCode1.nil? then
        hourCode1 = GameLibrary::hourCode()
    end

    if hourCode2.nil? then
        hourCode2 = GameLibrary::hourCode()
    end

    if hourCode1 and !(/^\d\d\d\d-\d\d-\d\d-\d\d$/.match(hourCode1)) then
        status 404
        return "Incorrect hour code (1)"
    end 

    if hourCode2 and !(/^\d\d\d\d-\d\d-\d\d-\d\d$/.match(hourCode2)) then
        status 404
        return "Incorrect hour code (2)"
    end 

    content_type 'text/plain'

    users = {}

    addScoreToUserLambda = lambda {|users, user, score|
        if users[user].nil? then
            users[user] = 0
        end
        users[user] = (users[user] + score).round(3)
        users
    }

    [
        GameLibrary::getGameAtHoursDataFolderPathsBetweenHourCodes(hourCode1, hourCode2)
            .sort
            .map{|hoursFolderpath|
                currentHour = File.basename(hoursFolderpath)
                userFleetsOrdered = GameLibrary::userFleetsForHour(currentHour)
                    .sort{|f1, f2| f1["gameScore"] <=> f2["gameScore"] }
                    .reverse
                score = 0.1/0.7
                lastValue = nil
                [
                    "",
                    File.basename(hoursFolderpath),
                    userFleetsOrdered.map{|userFleet|
                        currentUserValue = userFleet["gameScore"]
                        if currentUserValue != lastValue then
                            score = score*0.7 
                        end
                        lastValue = currentUserValue
                        users = addScoreToUserLambda.call(users, userFleet["username"], score)
                        "#{userFleet["username"].ljust(20)} , game score: #{"%10.3f" % currentUserValue} , leaderboard score increment: #{score.round(3)}"
                    }.join("\n")
                ].join("\n")
            }.join("\n") + "\n",
        "Summary: ",    
        users
            .keys
            .map{|username| [username, users[username]] }
            .sort{|p1,p2| p1[1] <=> p2[1] }
            .reverse
            .map{|p|
                username, score = p
                "   - #{username.ljust(20)} : #{score}"
            }.join("\n")
    ].join("\n") + "\n"
end

