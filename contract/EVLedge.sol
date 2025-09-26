// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title EVLedger
 * @dev Smart contract for tracking Electric Vehicle ownership, charging sessions, and energy transactions
 * @author EVLedger Team
 */
contract EVLedger {
    
    // Structure to represent an Electric Vehicle
    struct ElectricVehicle {
        string model;
        string batteryCapacity;
        address owner;
        uint256 totalEnergyConsumed;
        uint256 registrationTimestamp;
        bool isRegistered;
    }
    
    // Structure to represent a charging session
    struct ChargingSession {
        bytes32 vehicleId;
        address chargingStation;
        uint256 energyAmount; // in kWh
        uint256 cost; // in wei
        uint256 timestamp;
        bool isCompleted;
    }
    
    // State variables
    mapping(bytes32 => ElectricVehicle) public vehicles;
    mapping(uint256 => ChargingSession) public chargingSessions;
    mapping(address => bytes32[]) public ownerVehicles;
    mapping(bytes32 => uint256) public vehicleEnergyCredits; // Track energy credits separately
    
    uint256 public sessionCounter;
    uint256 public totalVehiclesRegistered;
    
    // Events
    event VehicleRegistered(bytes32 indexed vehicleId, address indexed owner, string model);
    event ChargingSessionStarted(uint256 indexed sessionId, bytes32 indexed vehicleId, address indexed station);
    event ChargingSessionCompleted(uint256 indexed sessionId, uint256 energyAmount, uint256 cost);
    event EnergyTransferCompleted(bytes32 indexed fromVehicle, bytes32 indexed toVehicle, uint256 amount);
    
    // Modifiers
    modifier onlyVehicleOwner(bytes32 _vehicleId) {
        require(vehicles[_vehicleId].owner == msg.sender, "Only vehicle owner can perform this action");
        _;
    }
    
    modifier vehicleExists(bytes32 _vehicleId) {
        require(vehicles[_vehicleId].isRegistered, "Vehicle not registered");
        _;
    }
    
    /**
     * @dev Register a new electric vehicle
     * @param _vehicleId Unique identifier for the vehicle (e.g., VIN hash)
     * @param _model Vehicle model name
     * @param _batteryCapacity Battery capacity specification
     */
    function registerVehicle(
        bytes32 _vehicleId,
        string memory _model,
        string memory _batteryCapacity
    ) external {
        require(!vehicles[_vehicleId].isRegistered, "Vehicle already registered");
        require(bytes(_model).length > 0, "Model cannot be empty");
        require(bytes(_batteryCapacity).length > 0, "Battery capacity cannot be empty");
        
        vehicles[_vehicleId] = ElectricVehicle({
            model: _model,
            batteryCapacity: _batteryCapacity,
            owner: msg.sender,
            totalEnergyConsumed: 0,
            registrationTimestamp: block.timestamp,
            isRegistered: true
        });
        
        ownerVehicles[msg.sender].push(_vehicleId);
        totalVehiclesRegistered++;
        
        emit VehicleRegistered(_vehicleId, msg.sender, _model);
    }
    
    /**
     * @dev Record a charging session for a vehicle (called by charging station)
     * @param _vehicleId The vehicle being charged
     * @param _energyAmount Amount of energy in kWh
     * @param _cost Cost of charging in wei
     */
    function recordChargingSession(
        bytes32 _vehicleId,
        uint256 _energyAmount,
        uint256 _cost
    ) external payable vehicleExists(_vehicleId) {
        require(_energyAmount > 0, "Energy amount must be greater than 0");
        require(msg.value >= _cost, "Insufficient payment for charging");
        
        sessionCounter++;
        
        chargingSessions[sessionCounter] = ChargingSession({
            vehicleId: _vehicleId,
            chargingStation: msg.sender,
            energyAmount: _energyAmount,
            cost: _cost,
            timestamp: block.timestamp,
            isCompleted: true
        });
        
        // Update vehicle's total energy consumed
        vehicles[_vehicleId].totalEnergyConsumed += _energyAmount;
        
        emit ChargingSessionStarted(sessionCounter, _vehicleId, msg.sender);
        emit ChargingSessionCompleted(sessionCounter, _energyAmount, _cost);
        
        // Refund excess payment
        if (msg.value > _cost) {
            payable(msg.sender).transfer(msg.value - _cost);
        }
    }
    
    /**
     * @dev Alternative function for vehicle owner to record their own charging session
     * @param _vehicleId The vehicle being charged
     * @param _energyAmount Amount of energy in kWh
     * @param _cost Cost of charging in wei
     * @param _chargingStation Address of the charging station
     */
    function recordOwnerChargingSession(
        bytes32 _vehicleId,
        uint256 _energyAmount,
        uint256 _cost,
        address _chargingStation
    ) external payable vehicleExists(_vehicleId) onlyVehicleOwner(_vehicleId) {
        require(_energyAmount > 0, "Energy amount must be greater than 0");
        require(msg.value >= _cost, "Insufficient payment for charging");
        require(_chargingStation != address(0), "Invalid charging station address");
        
        sessionCounter++;
        
        chargingSessions[sessionCounter] = ChargingSession({
            vehicleId: _vehicleId,
            chargingStation: _chargingStation,
            energyAmount: _energyAmount,
            cost: _cost,
            timestamp: block.timestamp,
            isCompleted: true
        });
        
        // Update vehicle's total energy consumed
        vehicles[_vehicleId].totalEnergyConsumed += _energyAmount;
        
        emit ChargingSessionStarted(sessionCounter, _vehicleId, _chargingStation);
        emit ChargingSessionCompleted(sessionCounter, _energyAmount, _cost);
        
        // Refund excess payment
        if (msg.value > _cost) {
            payable(msg.sender).transfer(msg.value - _cost);
        }
    }
    
    /**
     * @dev Transfer energy credits between vehicles (peer-to-peer energy sharing)
     * @param _fromVehicleId Source vehicle
     * @param _toVehicleId Destination vehicle
     * @param _energyAmount Amount of energy to transfer
     */
    function transferEnergyCredits(
        bytes32 _fromVehicleId,
        bytes32 _toVehicleId,
        uint256 _energyAmount
    ) external 
        vehicleExists(_fromVehicleId) 
        vehicleExists(_toVehicleId) 
        onlyVehicleOwner(_fromVehicleId) 
    {
        require(_fromVehicleId != _toVehicleId, "Cannot transfer to same vehicle");
        require(_energyAmount > 0, "Transfer amount must be greater than 0");
        require(vehicleEnergyCredits[_fromVehicleId] >= _energyAmount, "Insufficient energy credits to transfer");
        
        // Update energy credit balances
        vehicleEnergyCredits[_fromVehicleId] -= _energyAmount;
        vehicleEnergyCredits[_toVehicleId] += _energyAmount;
        
        emit EnergyTransferCompleted(_fromVehicleId, _toVehicleId, _energyAmount);
    }
    
    /**
     * @dev Add energy credits to a vehicle (e.g., from solar charging)
     * @param _vehicleId Vehicle identifier
     * @param _creditAmount Amount of credits to add
     */
    function addEnergyCredits(bytes32 _vehicleId, uint256 _creditAmount) 
        external 
        vehicleExists(_vehicleId) 
        onlyVehicleOwner(_vehicleId) 
    {
        require(_creditAmount > 0, "Credit amount must be greater than 0");
        vehicleEnergyCredits[_vehicleId] += _creditAmount;
    }
    
    /**
     * @dev Get available energy credits for a vehicle
     * @param _vehicleId Vehicle identifier
     * @return Available energy credits
     */
    function getAvailableEnergyCredits(bytes32 _vehicleId) public view vehicleExists(_vehicleId) returns (uint256) {
        return vehicleEnergyCredits[_vehicleId];
    }
    
    // View functions
    
    
    function getVehicleInfo(bytes32 _vehicleId) 
        external 
        view 
        vehicleExists(_vehicleId) 
        returns (
            string memory model,
            string memory batteryCapacity,
            address owner,
            uint256 totalEnergyConsumed,
            uint256 registrationTimestamp
        ) 
    {
        ElectricVehicle memory vehicle = vehicles[_vehicleId];
        return (
            vehicle.model,
            vehicle.batteryCapacity,
            vehicle.owner,
            vehicle.totalEnergyConsumed,
            vehicle.registrationTimestamp
        );
    }
    
    /**
     * @dev Get all vehicles owned by an address
     * @param _owner Owner address
     * @return Array of vehicle IDs
     */
    function getOwnerVehicles(address _owner) external view returns (bytes32[] memory) {
        return ownerVehicles[_owner];
    }
    
    
    function getChargingSession(uint256 _sessionId)
        external
        view
        returns (
            bytes32 vehicleId,
            address chargingStation,
            uint256 energyAmount,
            uint256 cost,
            uint256 timestamp,
            bool isCompleted
        )
    {
        require(_sessionId > 0 && _sessionId <= sessionCounter, "Invalid session ID");
        ChargingSession memory session = chargingSessions[_sessionId];
        return (
            session.vehicleId,
            session.chargingStation,
            session.energyAmount,
            session.cost,
            session.timestamp,
            session.isCompleted
        );
    }
    
    /**
     * @dev Get contract statistics
     * @return Total registered vehicles and charging sessions
     */
    function getContractStats() external view returns (uint256, uint256) {
        return (totalVehiclesRegistered, sessionCounter);
    }
}
