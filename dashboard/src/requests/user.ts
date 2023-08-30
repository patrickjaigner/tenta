"use client";

import useSWR from "swr";
import axios from "axios";
import { z } from "zod";
import Cookies from "js-cookie";

const userDataSchema = z
  .object({
    user_identifier: z.string(),
    access_token: z.string(),
  })
  .transform((data) => ({
    userIdentifier: data.user_identifier,
    accessToken: data.access_token,
  }));

export type UserDataType = z.infer<typeof userDataSchema>;

async function userFetcher(): Promise<UserDataType> {
  const userIdentifier = Cookies.get("userIdentifier");
  const accessToken = Cookies.get("accessToken");

  if (userIdentifier && accessToken) {
    return {
      userIdentifier,
      accessToken,
    };
  }

  // not authorized
  const error: any = new Error("Not authorized!");
  error.status = 403;
  throw error;
}

export function useUser() {
  const {
    data: userData,
    error,
    mutate,
  } = useSWR("userData", userFetcher, {
    refreshInterval: 0.01,
  });

  const loginUser = async (username: string, password: string) => {
    const { data } = await axios.post("http://127.0.0.1:8000/authentication", {
      user_name: username,
      password,
    });
    const userData = userDataSchema.parse(data);
    Cookies.set("userIdentifier", userData.userIdentifier);
    Cookies.set("accessToken", userData.accessToken);
    mutate(userData);
  };

  const authenticationState: "loading" | "loggedIn" | "loggedOut" = (() => {
    if (userData) {
      return "loggedIn";
    }
    if (error) {
      return "loggedOut";
    }
    return "loading";
  })();

  return {
    userData,
    authenticationState,
    logoutUser: () => {
      Cookies.remove("userIdentifier");
      Cookies.remove("accessToken");
      mutate(undefined);
    },
    loginUser,
  };
}