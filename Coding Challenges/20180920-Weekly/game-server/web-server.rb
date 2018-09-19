
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

# --  --------------------------------------------------

require_relative "library/BombsUtils.rb"
require_relative "library/MapUtils.rb"
require_relative "library/Navigation.rb"
require_relative "library/UserKeys.rb"
require_relative "library/UserFleet.rb"

# --  --------------------------------------------------

set :port, 14561
#set :public_folder, "path/to/www"

LUCILLE_INSTANCE = ENV["COMPUTERLUCILLENAME"]

if LUCILLE_INSTANCE.nil? then
    puts "Error: Environment variable 'COMPUTERLUCILLENAME' is not defined."
    exit
end

GAME_DATA_FOLDERPATH = "/Galaxy/DataBank/WeeklyCodingChallenges/20180920-Weekly/#{LUCILLE_INSTANCE}"
GAME_PARAMETERS_FILEPATH = File.dirname(__FILE__) + "/game-parameters.json"
$GAME_PARAMETERS = JSON.parse(IO.read(GAME_PARAMETERS_FILEPATH))

# -- --------------------------------------------------
# nslog

=begin

mapPoint = {
    "label" => "12345678",
    "coordinates" => [ 123 , 34.98]
}
puts UserFleet::spawnBattleCruiser(mapPoint, 12)

exit 

=end

# -- --------------------------------------------------

class GameLibrary

    # GameLibrary::hourCode()
    def self.hourCode()
        Time.new.strftime("%Y-%m-%d-%H")
    end

    # GameLibrary::getHoursFolderPaths()
    def self.getHoursFolderPaths()
        Dir.entries(GAME_DATA_FOLDERPATH)
            .select{|filename| filename[0,1]!="." }
            .map{|filename| "#{GAME_DATA_FOLDERPATH}/Timeline/#{filename}" }
    end

    # GameLibrary::getMapAtHourFolderpath(folderpath)
    def self.getMapAtHourFolderpath(folderpath)
        mapfilepath = "#{folderpath}/map.json"
        JSON.parse(IO.read(mapfilepath))
    end

    # GameLibrary::ensureGameFolderSetUpForThisHour()
    def self.ensureGameFolderSetUpForThisHour()

        folderpath = "#{GAME_DATA_FOLDERPATH}/Timeline/#{GameLibrary::hourCode()}"
        if !File.exists?(folderpath) then
            FileUtils.mkpath folderpath
        end

        mapfilepath = "#{folderpath}/map.json"
        return if File.exists?(mapfilepath)

        # ---------------------------------------
        # The Map
        map = {}
        map["mapId"] = SecureRandom.uuid
        map["timestamp"] = GameLibrary::hourCode()
        map["points"] = (1..$GAME_PARAMETERS["mapJumpPointsCardinality"]).map{|indx|
            {
                "label" => SecureRandom.hex(4),
                "coordinates" => [ rand * $GAME_PARAMETERS["mapSize"], rand * $GAME_PARAMETERS["mapSize"] ].map{|c| c.round(2) }
            }
        }
        File.open(mapfilepath, "w"){ |f| f.puts(JSON.pretty_generate(map)) }

        # ---------------------------------------
        # Game Parameters
        FileUtils.cp(GAME_PARAMETERS_FILEPATH, "#{folderpath}/game-parameters.json")

        # ---------------------------------------
        # The BBC Fleet

        folderpath

    end

    # GameLibrary::doUserFleetPointIncreaseForShipDestroyed(currentHour, username, nomenclature)
    def self.doUserFleetPointIncreaseForShipDestroyed(currentHour, username, nomenclature)
        userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)
        userFleet = ScoringUtils::userFleetPointIncreaseForShipDestroyed(userFleet, nomenclature)
        UserFleet::commitFleetToDisk(currentHour, username, fleet)
    end

    # GameLibrary::userFleetsInPlay(currentHour)
    def self.userFleetsInPlay(currentHour)
        Dir.entries("#{GAME_DATA_FOLDERPATH}/Timeline/#{currentHour}/fleets")
            .select{|filename| filename[-5,5]==".json" }
            .map{|filename| "#{GAME_DATA_FOLDERPATH}/Timeline/#{currentHour}/fleets/#{filename}" }
            .map{|filepath| IO.read(filepath) }
    end

end

# -- --------------------------------------------------
# Route

=begin

    HTTP error codes:
        401 Unauthorized
        403 Forbidden
        404 Not Found

=end

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
# Some admin

get '/game/v1/get-userkey/:username' do
    content_type 'text/plain'
    username = params["username"]

    if username.include?(":") then
        status 403
        return "Usernames cannot contain a colon (character ':')\n"
    end

    userKeysData = UserKeys::getUserKeysData()
    if userKeysData.any?{|record| record[0]==username } then
        status 403
        "There has already been a userkey issued for this username. If you think this is a mistake or you have forgotten your userkey, please contact Pascal.\n"
    else
        userkey = SecureRandom.hex(4)
        UserKeys::commitUserKey(username, userkey)
        [
            "username: #{username}",
            "userkey : #{userkey}"
        ].join("\n") + "\n"
    end
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

    userkey = params["userkey"]
    mapId = params["mapid"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end

    # ------------------------------------------------------
    # User Fleet validation

    if UserFleet::getUserFleetDataOrNull(currentHour, username) then
        status 403
        return "403: You cannot init a Capital Ship, you already have one for this hour\n"
    end

    # ------------------------------------------------------

    content_type 'application/json'

    mapPoint = MapUtils::getCurrentMap()["points"].sample
    capitalShipInitialEnergy = $GAME_PARAMETERS["fleetCapitalShipInitialEnergyLevel"]
    topUpChallengeDifficulty = $GAME_PARAMETERS["fleetCapitalShipTopUpChallengeDifficulty"]
    userFleet = UserFleet::spawnUserFleet(username, mapPoint, capitalShipInitialEnergy, topUpChallengeDifficulty)

    UserFleet::commitFleetToDisk(currentHour, username, userFleet)

    JSON.generate(userFleet)
end

get '/game/v1/:userkey/:mapid/capital-ship/top-up/:code' do

    userkey = params["userkey"]
    mapId = params["mapid"]
    code = params["code"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        status 404
        return "404: You do not yet have a fleet for this hour. (You should initiate one.)\n"
    end

    if !userFleet["shipInventory"]["capital"]["alive"] then
        status 403
        return "403: Your capital ship for this hour is dead.\n"
    end

    # ------------------------------------------------------    

    content_type 'application/json'

    if UserFleet::validateTopUpCode(currentHour, username, code) then
        if userFleet["shipInventory"]["capital"]["energyLevel"] + $GAME_PARAMETERS["fleetCapitalShipTopUpEnergyValue"] <= $GAME_PARAMETERS["fleetShipsMaxEnergy"]["capitalShip"] then
            topUpEnergyValue = $GAME_PARAMETERS["fleetCapitalShipTopUpEnergyValue"]
            difficulty = $GAME_PARAMETERS["fleetCapitalShipTopUpChallengeDifficulty"]
            UserFleet::topUpCapitalShipAndResetTopUpChallenge(currentHour, username, topUpEnergyValue)
            JSON.generate([true])
        else
            status 403
            return "403: Your code is correct, please keep it (!), but you cannot submit it at this time. Your ship has too much energy in reserve.\n"
        end
    else
        status 403
        return "403: Your code is not a solution to the challenge.\n"
    end
end

get '/game/v1/:userkey/:mapid/capital-ship/create-battle-cruiser' do

    userkey = params["userkey"]
    mapId = params["mapid"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        status 404
        return "404: You do not yet have a fleet for this hour. (You should initiate one.)\n"
    end

    if !userFleet["shipInventory"]["capital"]["alive"] then
        status 403
        return "403: Your capital ship for this hour is dead.\n"
    end

    # ------------------------------------------------------ 

    content_type 'application/json'

    battleCruiserBuildEnergyCost = $GAME_PARAMETERS["fleetBattleCruiserBuildEnergyCost"]
    battleCruiserInitialEnergyLevel = $GAME_PARAMETERS["fleetBattleCruiserInitialEnergyLevel"]

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)
    capitalShipCanPerformBattleShipCreation = userFleet["shipInventory"]["capital"]["energyLevel"] >= ( battleCruiserBuildEnergyCost + battleCruiserInitialEnergyLevel )
    if capitalShipCanPerformBattleShipCreation then
        userFleet["shipInventory"]["capital"]["energyLevel"] = userFleet["shipInventory"]["capital"]["energyLevel"] - ( battleCruiserBuildEnergyCost + battleCruiserInitialEnergyLevel )
        mapPoint = MapUtils::getCurrentMap()["points"].sample
        battleCruiser = UserFleet::spawnBattleCruiser(mapPoint, battleCruiserInitialEnergyLevel)
        userFleet["shipInventory"]["battleCruisers"] << battleCruiser
        UserFleet::commitFleetToDisk(currentHour, username, userFleet)
        JSON.generate(battleCruiser)
    else
        status 403
        "403: Your capital ship doesn't have enough energy to complete the construction of a battle cruiser. You have #{userFleet["shipInventory"]["capital"]["energyLevel"]} but you need #{(battleCruiserBuildEnergyCost+battleCruiserInitialEnergyLevel)}\n"
    end

end

get '/game/v1/:userkey/:mapid/capital-ship/create-energy-carrier/:energyamount' do

    userkey = params["userkey"]
    mapId = params["mapid"]

    energyamount = params["energyamount"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        status 404
        return "404: You do not yet have a fleet for this hour. (You should initiate one.)\n"
    end

    if !userFleet["shipInventory"]["capital"]["alive"] then
        status 403
        return "403: Your capital ship for this hour is dead.\n"
    end

    if energyamount > $GAME_PARAMETERS["fleetShipsMaxEnergy"]["energyCarrier"] then
        status 403
        return "403: You are creating a carrier with too much energy. Upper limit is #{$GAME_PARAMETERS["fleetShipsMaxEnergy"]["energyCarrier"]} units of energy.\n"        
    end

    # ------------------------------------------------------ 

    content_type 'application/json'

    carrierBuildEnergyCost = $GAME_PARAMETERS["fleetEnergyCarrierBuildEnergyCost"]
    carrierInitialEnergyLevel = energyamount 

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)
    capitalShipCanPerformCarrierCreation = userFleet["shipInventory"]["capital"]["energyLevel"] >= ( carrierBuildEnergyCost + carrierInitialEnergyLevel )
    if capitalShipCanPerformCarrierCreation then
        userFleet["shipInventory"]["capital"]["energyLevel"] = userFleet["shipInventory"]["capital"]["energyLevel"] - ( carrierBuildEnergyCost + carrierInitialEnergyLevel )
        mapPoint = MapUtils::getCurrentMap()["points"].sample
        energyCarrier = UserFleet::spawnEnergyCarrier(mapPoint, carrierInitialEnergyLevel)
        userFleet["shipInventory"]["energyCarriers"] << energyCarrier
        UserFleet::commitFleetToDisk(currentHour, username, userFleet)
        JSON.generate(energyCarrier)
    else
        status 403
        "403: Your capital ship doesn't have enough energy to complete the construction of an energy carrier carrying #{carrierInitialEnergyLevel}. You have #{userFleet["shipInventory"]["capital"]["energyLevel"]} but you need #{(carrierBuildEnergyCost+carrierInitialEnergyLevel)}\n"
    end

    "{}"
end

get '/game/v1/:userkey/:mapid/jump/:shipuuid/:targetpointlabel' do

    userkey = params["userkey"]
    mapId = params["mapid"]

    shipuuid = params["shipuuid"]
    targetPointLabel = params["targetpointlabel"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end

    # ------------------------------------------------------
    # Map Validation

    map = MapUtils::getCurrentMap()    

    targetMapPoint = MapUtils::getPointForlabelAtMapOrNull(label, map)
    if targetMapPoint.nil? then
        status 404
        return "404: The specified point doesn't exist\n"
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        status 404
        return "404: You do not yet have a fleet for this hour. (You should initiate one.)\n"
    end

    # Need to check whether we own a ship of with that uuid, and retrieve it.
    ship = UserFleet::getShipPerUUIDOrNull(currentHour, username, uuid)
    if ship.nil? then
        status 404
        return "404: Your fleet has no ship with this uuid.\n"
    end

    # Need to check whether the ship is alive ot not
    if !ship["alive"] then
        status 403
        return "403: The ship is dead.\n"
    end    

    # In the current version of the game energy carriers need the capital ship to be alive 
    # in order to be controlled. Therfore we record whether or not the capital is alive.

    if ship["nomenclature"] == "energyCarrier" then
        if !userFleet["shipInventory"]["capital"]["alive"] then
            status 403
            return "403: Your capital ship is dead. You cannot jump energy carriers in that case.\n"
        end 
    end

    sourceMapPoint = ship["location"]

    jec = Navigation::jumpEnergyCost(sourceMapPoint, targetMapPoint, ship["nomenclature"])

    # Need to check whether the ship has enough energy left to jump
    if !ship["energyLevel"] < jec then
        status 403
        return "403: The ship doesn't have enough energy for this jump. Available: #{ship["energyLevel"]}. Required: #{jec}.\n"
    end    

    # ------------------------------------------------------
    
    # Now performing the jump
    ship["location"] = targetMapPoint
    ship["energyLevel"] = ship["energyLevel"] - jec

    userFleet = UserFleet::insertOrUpdateShipAtFleet(userFleet, ship)
    UserFleet::commitFleetToDisk(currentHour, username, userFleet)

    content_type 'application/json'
    JSON.pretty_generate(userFleet)

end

get '/game/v1/:userkey/:mapid/energy-transfer-type1/:energycarriershipuuid/:energylevel' do

    userkey = params["userkey"]
    mapId = params["mapid"]

    energyCarrierShipUUID = params["energycarriershipuuid"]
    energyLevel = params["energylevel"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        status 404
        return "404: You do not yet have a fleet for this hour. (You should initiate one.)\n"
    end

    energyCarrier = UserFleet::getShipPerUUIDOrNull(currentHour, username, energyCarrierShipUUID)
    capital = userFleet["shipInventory"]["capital"]

    if energyCarrier.nil? then
        status 404
        return "404: Your fleet has no ship with uuid #{energyCarrierShipUUID}.\n"
    end

    if !energyCarrier["alive"] then
        status 403
        return "403: The energy carrier is dead.\n"
    end

    if !capital["alive"] then
        status 403
        return "403: Your capital ship is dead.\n"
    end

    if capital["location"]["label"] != energyCarrier["location"]["label"] then
        status 403
        return "403: You cannot transfer energy between the two ships, they are not at the same map location.\n"        
    end

    if capital["energyLevel"] < energyLevel then
        status 403
        return "403: Your capital ship doesn't have enough energy for this transfer.\n"
    end    

    if (energyCarrier["energyLevel"]+energyLevel) > $GAME_PARAMETERS["fleetShipsMaxEnergy"]["energyCarrier"] then
        status 403
        return "403: You are creating a carrier with too much energy. Upper limit is #{$GAME_PARAMETERS["fleetShipsMaxEnergy"]["energyCarrier"]} units of energy.\n"       
    end        

    # ------------------------------------------------------

    capital["energyLevel"] = capital["energyLevel"] - energyLevel
    energyCarrier["energyLevel"] = energyCarrier["energyLevel"] + energyLevel

    userFleet["shipInventory"]["capital"] = capital
    userFleet = UserFleet::insertOrUpdateShipAtFleet(userFleet, energyCarrier)
    UserFleet::commitFleetToDisk(currentHour, username, userFleet)

    JSON.pretty_generate([ energyCarrier, capital ])

end

get '/game/v1/:userkey/:mapid/energy-transfer-type2/:energycarriershipuuid/:battlecruisershipuuid' do

    userkey = params["userkey"]
    mapId = params["mapid"]

    energyCarrierShipUUID = params["energycarriershipuuid"]
    battleCruiserShipUUID = params["battlecruisershipuuid"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        status 404
        return "404: You do not yet have a fleet for this hour. (You should initiate one.)\n"
    end

    energyCarrier = UserFleet::getShipPerUUIDOrNull(currentHour, username, energyCarrierShipUUID)
    battleCruiser = UserFleet::getShipPerUUIDOrNull(currentHour, username, battleCruiserShipUUID)

    if energyCarrier.nil? then
        status 404
        return "404: Your fleet has no ship with uuid #{energyCarrierShipUUID}.\n"
    end

    if battleCruiser.nil? then
        status 404
        return "404: Your fleet has no ship with uuid #{battleCruiserShipUUID}.\n"
    end

    if !energyCarrier["alive"] then
        status 403
        return "403: The energy carrier is dead.\n"
    end

    if !battleCruiser["alive"] then
        status 403
        return "403: The battle cruiser is dead.\n"
    end

    if battleCruiser["location"]["label"] != energyCarrier["location"]["label"] then
        status 403
        return "403: You cannot transfer energy between the two ships, they are not at the same map location.\n"        
    end

    if energyCarrier["energyLevel"] == 0 then
        status 403
        return "403: The energy carrier is empty.\n"
    end    

    if (battleCruiser["energyLevel"]+energyCarrier["energyLevel"]) > $GAME_PARAMETERS["fleetShipsMaxEnergy"]["battleCruiser"] then
        status 403
        return "403: You cannot perform this transfer as it would exceed the battle cruiser capacity.\n"       
    end 

    # ------------------------------------------------------

    battleCruiser["energyLevel"] = battleCruiser["energyLevel"] + energyCarrier["energyLevel"]
    energyCarrier["energyLevel"] = 0

    userFleet = UserFleet::insertOrUpdateShipAtFleet(userFleet, battleCruiser)
    userFleet = UserFleet::insertOrUpdateShipAtFleet(userFleet, energyCarrier)
    UserFleet::commitFleetToDisk(currentHour, username, userFleet)

    JSON.pretty_generate([ energyCarrier, battleCruiser ])

end

get '/game/v1/:userkey/:mapid/bomb/:battlecruisershipuuid/:targetpointlabel' do

    userkey = params["userkey"]

    battleCruiserShipUUID = params["battlecruisershipuuid"]
    targetpointlabel = params["targetpointlabel"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end    

    # ------------------------------------------------------
    # Map Validation

    map = MapUtils::getCurrentMap()

    targetMapPoint = MapUtils::getPointForlabelAtMapOrNull(targetpointlabel, map)
    if targetMapPoint.nil? then
        status 404
        return "404: The specified point doesn't exist\n"
    end

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        status 404
        return "404: You do not yet have a fleet for this hour. (You should initiate one.)\n"
    end

    battleCruiser = UserFleet::getShipPerUUIDOrNull(currentHour, username, battleCruiserShipUUID)

    if battleCruiser.nil? then
        status 404
        return "404: Your fleet has no ship with uuid #{battleCruiserShipUUID}.\n"
    end

    if !battleCruiser["alive"] then
        status 403
        return "403: The battle cruiser is dead.\n"
    end

    # ------------------------------------------------------
    # At this point we can attempt shooting

    if battleCruiser["energyLevel"] < ( $GAME_PARAMETERS["fleetBattleCruiserBombBuildingCost"] + $GAME_PARAMETERS["fleetBattleCruiserBombNominalEnergy"] ) then
        status 403
        return "403: Your cruiser doesn't have enough energy to complete the construction of a bomb.\n"        
    end

    battleCruiser["energyLevel"] = battleCruiser["energyLevel"] - ( $GAME_PARAMETERS["fleetBattleCruiserBombBuildingCost"] + $GAME_PARAMETERS["fleetBattleCruiserBombNominalEnergy"] )
    userFleet = UserFleet::insertOrUpdateShipAtFleet(userFleet, battleCruiser)

    # Ok, now time to do damage

    distanceToTargetPoint = MapUtils::distanceBetweenTwoMapPoints(battleCruiser["location"], targetMapPoint)
    bombEffectiveEnergy = BombsUtils::bombEffectiveEnergy($GAME_PARAMETERS["fleetBattleCruiserBombNominalEnergy"], distanceToTargetPoint)

    attackerDamageReport = []

    GameLibrary::userFleetsInPlay(currentHour)
        .each{|otherPlayerUserFleet|
            UserFleet::userShipsWithinDisk(currentHour, otherPlayerUserFleet["username"], battleCruiser["location"], 0)
                .each{|targetShip|
                    otherPlayerUserFleet, targetShip, damageCausedForAttackerReport = UserFleet::registerShipTakingBombImpact(otherPlayerUserFleet, battleCruiser["location"], username, targetShip)
                    attackerDamageReport << damageCausedForAttackerReport
                    otherPlayerUserFleet = UserFleet::insertOrUpdateShipAtFleet(otherPlayerUserFleet, targetShip)
                }
            UserFleet::commitFleetToDisk(currentHour, otherPlayerUserFleet["username"], otherPlayerUserFleet)
        }

    JSON.pretty_generate(attackerDamageReport)
end

get '/game/v1/:userkey/:mapid/space-probe/:battlecruisershipuuid' do

    userkey = params["userkey"]

    battleCruiserShipUUID = params["battlecruisershipuuid"]

    currentHour = GameLibrary::hourCode()

    # ------------------------------------------------------
    # User Credentials and Map Validity Checks

    username = UserKeys::getUsernameFromUserkeyOrNull(userkey)

    if !username.nil? then
        status 401
        return "401: Invalid userkey\n"
    end

    if MapUtils::getCurrentMap()["mapId"] != mapId then
        status 404
        return "404: Map not found (mapId is incorrect or outdated)\n"
    end    

    # ------------------------------------------------------
    # User Fleet validation

    userFleet = UserFleet::getUserFleetDataOrNull(currentHour, username)

    if userFleet.nil? then
        status 404
        return "404: You do not yet have a fleet for this hour. (You should initiate one.)\n"
    end

    battleCruiser = UserFleet::getShipPerUUIDOrNull(currentHour, username, battleCruiserShipUUID)

    if battleCruiser.nil? then
        status 404
        return "404: Your fleet has no ship with uuid #{battleCruiserShipUUID}.\n"
    end

    if !battleCruiser["alive"] then
        status 403
        return "403: The battle cruiser is dead.\n"
    end

    # ------------------------------------------------------
    # At this point we can attempt shooting

    spaceProbeResults = {
        "unixtime" => Time.new.to_f,
        "datetime" => Time.now.utc.iso8601,
        "results"  => []
    }

    GameLibrary::userFleetsInPlay(currentHour)
        .each{|otherPlayerUserFleet|
            UserFleet::userShipsWithinDisk(currentHour, otherPlayerUserFleet["username"], battleCruiser["location"], 300)
                .each{|ship|
                    spaceProbeResultItem = {
                        "location" => ship["location"],
                        "nomenclature" => ship["nomenclature"],
                        "username" => otherPlayerUserFleet["username"]
                    }
                    spaceProbeResults << spaceProbeResultItem
                }
        }

    JSON.pretty_generate(spaceProbeResults)
end

