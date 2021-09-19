pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IDrawCalculator.sol";

contract OracleManager is IDrawCalculator, Ownable {

  IDrawCalculator immutable calculator;

  constructor (

  )

}